/* eslint-env jquery */
$(function() {
  const panel = $('#contact_form_editor')
  const myFields = panel.find('#my_fields')

  myFields.sortable({ handle: '.panel-sortable' })
  panel.find('#fields_available a').click(function() {
    showLoading()
    myFields.attr('data-cid', parseInt(myFields.attr('data-cid')) + 1)
    $.get(
      panel.find('#fields_available').attr('data-remote_url'),
      { kind: $(this).attr('data-field-type'), cid: 'c' + myFields.attr('data-cid') },
      function(res) {
        res = $(res)
        myFields.append(res)
        res.find('.options_sortable').sortable({ handle: '.options-sortable' })
        res.find('.add_option').click().click()
        res.find('.translatable').Translatable(ADMIN_TRANSLATIONS)
        return hideLoading()
      })
    return false
  })

  panel.on('click', '.add_option', function() {
    const list = $(this).prev('ul')
    list.attr('data-options-count', parseInt(list.attr('data-options-count')) + 1)

    const clone = list.children().first().clone().removeClass('hidden')
    clone.find('input').prop('disabled', false).each(function() {
      return $(this).attr('name', $(this).attr('name').replace('[0]', '[' + list.attr('data-options-count') + ']'))
    })

    list.append(clone)
    clone.find('.translatable').Translatable(ADMIN_TRANSLATIONS)
    return false
  })

  panel.on('click', '.option-delete', function() {
    $(this).closest('li').remove()
    return false
  })

  panel.on('click', '.panel-delete', function() {
    $(this).closest('li.panel').fadeOut('slow', function() {
      return $(this).remove()
    })
    return false
  })

  panel.on('click', '.html_btn', function() {
    $(this).hide().next().hide().removeClass('hidden').fadeIn()
    return false
  })

  myFields.find('.options_sortable').sortable({ handle: '.options-sortable' })
  return panel.find('.translatable').Translatable(ADMIN_TRANSLATIONS)
})
