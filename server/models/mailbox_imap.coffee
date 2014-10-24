Mailbox = require './mailbox'
Message = require './message'
Promise = require 'bluebird'
ImapScheduler = require '../processes/imap_scheduler'
ImapReporter  = require '../processes/imap_reporter'
log = require('../utils/logging')('models:mailbox_imap')
_ = require 'lodash'
mailutils = require '../utils/jwz_tools'
{Break} = require '../utils/errors'

Mailbox::doASAPWithBox = (gen) ->
    ImapScheduler.instanceFor(@accountID)
    .then (scheduler) => scheduler.doASAPWithBox this, gen

Mailbox::doLaterWithBox = (gen) ->
    ImapScheduler.instanceFor(@accountID)
    .then (scheduler) => scheduler.doLaterWithBox this, gen


Mailbox::imap_fetchMails = (limitByBox) ->
    @imap_refreshStep limitByBox


FETCH_AT_ONCE = 1000
Mailbox::imap_refreshStep = (limitByBox, laststep) ->

    step = null
    boxID = @id
    box = @
    reporter = null

    @doLaterWithBox (imap, imapbox) ->
        laststep ?= min: imapbox.uidnext + 1

        throw new Break() if laststep.min is 1

        step =
            max: Math.max 1, laststep.min - 1
            min: Math.max 1, laststep.min - FETCH_AT_ONCE

        if limitByBox
            step.min = Math.max 1, laststep.min - limitByBox

        log.info "IMAP REFRESH STEP", imapbox.uidnext, box.label, step.min, step.max

        Promise.all [
            imap.search [['UID', "#{step.min}:#{step.max}"]]
            .then (UIDs) -> imap.fetchMetadata(UIDs)

            Message.UIDsInRange boxID, step.min, step.max
        ]

    .spread (imapUIDs, cozyIds) =>

        ops =
            toFetch: []
            toRemove: []
            flagsChange: []

        for uid, imapMessage of imapUIDs
            if cozyMessage = cozyIds[uid] # this message is already in cozy
                if _.xor(imapMessage[1], cozyMessage[1]).length
                    id = cozyMessage[0]
                    ops.flagsChange.push id: id, flags: imapMessage[1]

            else # this message isnt in this box in cozy
                # add it to be fetched
                ops.toFetch.push {uid: parseInt(uid), mid: imapMessage[0]}

        for uid, cozyMessage of cozyIds
            unless imapUIDs[uid]
                ops.toRemove.push id = cozyMessage[0]

        return ops

    .tap (ops) ->

        nbTasks = ops.toFetch.length +
                ops.toRemove.length +
                ops.flagsChange.length

        if nbTasks > 0
            reporter = ImapReporter.boxFetch @, nbTasks

    .tap (ops) ->
        Promise.serie ops.toRemove, (id) ->
            Message.removeFromMailbox id, box
            .catch (err) -> reporter.onError err
            .tap -> reporter.addProgress 1
            .delay 100 # let the DS breath

    .tap (ops) ->
        Promise.serie ops.flagsChange, (change) ->
            Message.applyFlagsChanges change.id, change.flags
            .catch (err) -> reporter.onError err
            .tap -> reporter.addProgress 1
            .delay 100 # let the DS breath

    .tap (ops) ->
        Promise.map ops.toFetch, (msg) ->
            Message.byMessageId msg.mid
            .then (existing) =>
                if existing then existing.addToBox boxID, msg.uid
                else box.imap_fetchOneMail msg.uid
            .catch (err) -> reporter.onError err
            .tap -> reporter.addProgress 1
            .delay 100 # let the DS breath

    .finally -> reporter?.onDone()

    # loop until we have all messages
    .then(
        (ok)  => @imap_refreshStep null, step unless limitByBox
        (err) ->
            if err instanceof Break then 'done'
            else throw err
    )


Mailbox::imap_fetchOneMail = (uid) ->
    @doLaterWithBox (imap) =>
        imap.fetchOneMail uid

    .then (mail) => Message.createFromImapMessage mail, this, uid
    .tap => log.info "MAIL #{@path}##{uid} CREATED"

# Public: remove a mail in the given box
# used for drafts
#
# uid - {Number} the message to remove
#
# Returns a {Promise} for the UID of the created mail
Mailbox::imap_removeMail = (uid) ->
    @doASAPWithBox (imap) =>
        imap.expunge uid, @path

Mailbox::recoverChangedUIDValidity = (imap, accountID) ->
    box = this
    imap.openBox @path
    .then -> imap.fetchBoxMessageIds()
    .then (map) ->
        uids = _.keys(map)
        reporter = ImapReporter.recoverUIDValidty box, uids.length
        Promise.serie uids, (newUID) ->
            messageID = mailutils.normalizeMessageID map[newUID]
            Message.rawRequestPromised 'byMessageId',
                key: [accountID, messageID]
                include_docs: true
            .get(0)
            .then (row) ->
                return unless row
                mailboxIDs = row.doc.mailboxIDs
                mailboxIDs[box.id] = newUID
                msg = new Message(row.doc)
                msg.updateAttributesPromised {mailboxIDs}
            .tap -> reporter.addProgress 1
            .catch (err) ->
                reporter.onError err
                throw err