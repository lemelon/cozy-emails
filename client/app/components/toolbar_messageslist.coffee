{aside, i, button} = React.DOM
classer = React.addons.classSet

FiltersToolbarMessagesList = require './toolbar_messageslist_filters'
SearchToolbarMessagesList  = require './toolbar_messageslist_search'
ActionsToolbarMessagesList = require './toolbar_messageslist_actions'


module.exports = ToolbarMessagesList = React.createClass
    displayName: 'ToolbarMessagesList'

    propTypes:
        accountID:            React.PropTypes.string.isRequired
        mailboxID:            React.PropTypes.string.isRequired
        mailboxes:            React.PropTypes.object.isRequired
        messages:             React.PropTypes.object.isRequired
        edited:               React.PropTypes.bool.isRequired
        selected:             React.PropTypes.object.isRequired
        displayConversations: React.PropTypes.bool.isRequired
        toggleEdited:         React.PropTypes.func.isRequired
        toggleAll:            React.PropTypes.func.isRequired


    render: ->
        aside role: 'toolbar',
            button
                role:                     'menuitem'
                'aria-selected':          @props.edited
                onClick:                  @props.toggleEdited

                i className: classer
                    fa:                  true
                    'fa-square-o':       not @props.edited
                    'fa-check-square-o': @props.edited

            if @props.edited
                ActionsToolbarMessagesList
                    mailboxID:            @props.mailboxID
                    mailboxes:            @props.mailboxes
                    messages:             @props.messages
                    selected:             @props.selected
                    displayConversations: @props.displayConversations
            unless @props.edited
                FiltersToolbarMessagesList
                    accountID: @props.accountID
                    mailboxID: @props.mailboxID
            unless @props.edited
                SearchToolbarMessagesList
                    accountID: @props.accountID
                    mailboxID: @props.mailboxID
