$ ->
  panel = $('#contact_form_editor')
  my_fields = panel.find('#my_fields')
  my_fields.sortable({handle: ".panel-sortable"})
  panel.find('#fields_available a').click ->
    showLoading()
    my_fields.attr('data-cid', parseInt(my_fields.attr('data-cid')) + 1)
    $.get(panel.find('#fields_available').attr('data-remote_url'), {kind: $(this).attr('data-field-type'), cid: 'c'+my_fields.attr('data-cid')}, (res)->
      res = $(res)
      my_fields.append(res)
      res.find('.options_sortable').sortable({handle: ".options-sortable"})
      res.find('.add_option').click().click()
      res.find('.translatable').Translatable(ADMIN_TRANSLATIONS)
      hideLoading()
    )
    return false

  panel.on('click', '.add_option', ->
    list = $(this).prev('ul')
    list.attr('data-options-count', parseInt(list.attr('data-options-count'))+1)
    clone = list.children().first().clone().removeClass('hidden')
    clone.find('input').prop('disabled', false).each(->
      $(this).attr('name', $(this).attr('name').replace('[0]', '['+list.attr('data-options-count')+']'))
    )
    list.append(clone)
    clone.find('.translatable').Translatable(ADMIN_TRANSLATIONS)
    return false
  )

  panel.on('click', '.option-delete', ->
    $(this).closest('li').remove()
    return false
  )

  panel.on('click', '.panel-delete', ->
    $(this).closest('li.panel').fadeOut('slow', ->
      $(this).remove()
    )
    return false
  )

  panel.on('click', '.html_btn', ->
    $(this).hide().next().hide().removeClass('hidden').fadeIn()
    return false
  )

  my_fields.find('.options_sortable').sortable({handle: ".options-sortable"})
  panel.find('.translatable').Translatable(ADMIN_TRANSLATIONS)