_ = require 'lodash'
bootbox = require 'bootbox'


findError = (obj) ->
    for k, v of obj
        if _.isObject v
            error = findError v
            if error == true
                return k
            else if error
                return "#{k}.#{error}"
        else if v
            return true
    false

clearData = (data, errors) ->
    return if not _.isObject data
    # Одно поле содержит массив значений. Например, метки.
    return if _.isArray(data) and _.isPlainObject errors
    for k, v of data
        if _.isObject(errors[k]) and not _.startsWith k, '_'
            continue if errors[k]._cleanInside == false
            clearData data[k], errors[k]
            if _.isObject(data[k]) and _.isEmpty(data[k])
                delete data[k]
        else
            if _.isArray data
                data.splice k, 1
            else
                delete data[k]


class DField
    init: ->
        @path = @getAttribute('path') or @model.get('path') or @defaultPath
        form = @parent
        while 'formModel' not of form
            form = form.parent
            if not form
                form = @parent
                break
        @formModel = form.formModel or form.model
#        @model.ref 'value', @formModel.at @path
        @model.set 'id', form.prefix + @path
        @model.start 'value', @formModel.at(@path),
            get: (value) -> value
            set: (value) ->
                if _.isString value
                    [value.trim()]
                else
                    [value]

        if 'ref' of @model.get()
            @model.ref 'value', 'ref'

        @model.ref 'submitted', @formModel.at '_submitted'
        @model.ref 'errors', @formModel.at "_errors.#{@path}"
        form.on 'reset', => @reset()
        @reset()

        attributeContext = @context.forAttribute 'path'
        if _.isObject attributeContext?.attributes.path
            dependencies = attributeContext.attributes.path.dependencies attributeContext
        else
            dependencies = []
        checkExpr = =>
            value = @getAttribute('path')
            return unless @path != value
            @path = value
            @model.set 'id', form.prefix + @path
            @model.start 'value', @formModel.at(@path),
                get: (value) -> value
                set: (value) ->
                    if _.isString value
                        [value.trim()]
                    else
                        [value]
    
            @model.ref 'errors', @formModel.at "_errors.#{@path}"

        @eventModel = @model.scope()
        for segments in dependencies
            @eventModel.on 'all', segments.join('.'), checkExpr
            
        @model.set 'errors._cleanInside', false
        @model.start 'errors.required', 'required', 'value', (required, value) ->
            return unless required
            if _.isString value
                not value
            else
                not value?

        @model.on 'change', 'value', => @emit 'change'

        @on 'destroy', =>
            @model.del 'errors'
            # Не удаляем значение, чтобы пользователь мог вернуть поле обратно и продолжить редактирование.
            # Лишние значения должны удаляться формой при сабмите. И не из модели, а из временно создаваемого объекта.
            # @model.del 'value'

    reset: ->
        if not @model.get('value')?
            @model.setDiff 'value', @getAttribute 'initial'
#        @model.setNull 'errors', {}

    findError: findError


class Radio
    init: ->
        for o in @getAttribute 'options'
            continue if not o.default
            if not @model.get('value')?
                @model.set 'value', o.value
            @model.on 'change', 'value', (value) =>
                if not value?
                    @model.set 'value', o.value
            break


module.exports = class
    view: __dirname
    init: ->
        @setMaxListeners 50  # Every field subscribes for 'reset' event
        @model = @parent.model
        @_scope = @parent._scope

        @path = @getAttribute('path') or 'data'
        if @path == 'data'
            @prefix = ''
        else
            @prefix = @path + '.'
        @formModel = @model.at @path
#        if 'data' not of @model.get()
#            @model.ref 'data', @parent.model.at 'data'
#            @model.ref 'submitted', @parent.model.at 'submitted'
#            @model.ref 'errors', @parent.model.at 'errors'
#        @model.setNull 'errors', {}
        @formModel.start '_cleaned', @formModel, (data) ->
            return if not data?._errors
            data = _.cloneDeep data
            clearData data, data._errors
            data

        for m in _.functionsIn @parent.__proto__
            if m not of @ and m not in ['create', 'subscribe']
                @[m] = @parent[m].bind @parent

    submit: ->
#        @model.set 'submitted', true
#        errors = @model.get 'errors'
#        return if findTrue errors
#        data = @model.getDeepCopy 'data'
#        clearData data, @model.get 'errors'
#        @emit 'submit', data
#        @model.set 'submitted', false
        @formModel.set '_submitted', true
        errors = @formModel.get '_errors'
        error = findError errors
        if error
            if elem = document.getElementById(error) # Здесь нужна поддержка вложенных форм
                elem.parentNode.scrollIntoView()
            else
                window.scrollTo 0, 0
            return
        data = @formModel.getDeepCopy()
        clearData data, @formModel.get '_errors'
        @emit 'submit', data, (err) =>
            return bootbox.alert err if err
            @emit 'successSubmit', data
#        @formModel.set '_submitted', false

    reset: ->
        @formModel.set {}
        @emit 'reset'


    components: [
        class extends DField
            name: 'field'

        class extends DField
            name: 'field-input'

        class extends DField
            name: 'field-email'
            init: ->
                super()
                re = /^[-a-zA-Z._0-9]+@[-a-zA-Z._0-9]+\.[a-zA-Z]+$/
                @model.start 'errors.format', 'value', 'disableCheck', (value, disableCheck) ->
                    return unless value and not disableCheck
                    not re.test value

        class extends DField
            name: 'field-checkbox'

        class extends Radio
            name: 'radio'

        class extends Radio
            name: 'radio-btn-group'

        class extends DField
            name: 'field-radio'

        class extends DField
            name: 'field-radio-btn-group'

        class extends DField
            name: 'field-textarea'

        class extends DField
            name: 'field-daterangepicker'
            reset: ->
                super()
                @model.setNull 'errors.start', {}
                @model.setNull 'errors.end', {}

        class extends DField
            name: 'field-hidden'
    ]

module.exports.DField = DField
module.exports.DFieldSet = class
    init: ->
        path = @getAttribute('path') or @defaultPath
        form = @parent
        while 'formModel' not of form
            form = form.parent

        @prefix = form.prefix + path + '.'
        @formModel = form.formModel.at path
        @formModel.ref '_submitted', form.formModel.at '_submitted'
        @formModel.ref '_errors', form.formModel.at '_errors.' + path
        if path.startsWith '_'
            @formModel.start '_cleaned', @formModel, (data) ->
                return if not data?._errors
                data = _.cloneDeep data
                clearData data, data._errors
                data
        else
            @formModel.ref '_cleaned', form.formModel.at '_cleaned.' + path
        @model.ref 'data', @formModel

        @on 'destroy', =>
            @formModel.removeRef '_submitted'