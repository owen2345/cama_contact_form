# frozen_string_literal: true

# Public endpoint that receives a form submission (`save_form`) and redisplays the form on refusal.
class Plugins::CamaContactForm::FrontController < CamaleonCms::Apps::PluginsFrontController
  include Plugins::CamaContactForm::MainHelper
  include Plugins::CamaContactForm::ContactFormControllerConcern

  # here add your custom functions
  def save_form
    flash[:contact_form] = {}
    # `parent_id: nil` restricts the lookup to authored forms. `contact_forms` also holds every stored
    # response (a child row, `parent_id` set), and a response's `fields` is empty, so it sails through
    # validation -- submitting a response's id would write a fresh child row and open it its own throttle
    # budget, so the flood cap could be lapped by walking the (sequential, guessable) response ids.
    @form = current_site.contact_forms.find_by(id: params[:id], parent_id: nil)
    fields = params[:fields]
    errors = []
    success = []

    args = { form: @form, values: fields, flag: true }
    hooks_run('contact_form_before_submit', args)
    if args[:flag]
      # Refuse a flood before it can mail, upload or write a row. Keyed on @form, so a bogus id
      # (which perform_save_form rejects anyway, cheaply) is left to it rather than throttled against
      # no form.
      if @form.present? && submission_over_limit?(@form)
        errors << t('.too_many_requests',
                    default: 'Too many submissions from your network. Please wait a few minutes and try again.')
      else
        perform_save_form(@form, fields, success, errors)
      end
      if success.present?
        flash[:contact_form][:notice] = success.join('<br>')
        # Success and errors coexist on exactly one path: the submission stored and mailed, but a
        # file failed its upload (over core's size cap, or refused by the content scan). Showing
        # only the notice told the visitor everything arrived when a file they sent was dropped --
        # the errors ride along so the success never silently trims the submission.
        flash[:contact_form][:error] = errors.join('<br>') if errors.present?
      else
        flash[:contact_form][:error] = errors.join('<br>')
        # Redisplaying the submission is the only reason it ever reaches the page, so a submission
        # containing anything malign is refused whole and echoed back not at all. Filtering it down
        # to the safe fields would be more work for a worse result: the visitor gets a half-filled
        # form, and every future edit to the rendering has to stay in step with the filter.
        #
        # Stamped with the form it was judged against. The gate walks `@form.fields` for the form
        # named by params[:id], but the redisplay page hands flash[:values] to *every* shortcode on
        # it, and auto-generated cids are `c1, c2, …` in every form -- so a value cleared as textarea
        # content for one form was being rendered into a value attribute by another.
        #
        # `@form` is whatever `find_by_id` returned, which is nil for a deleted or bogus id -- a
        # POST anyone can make without credentials. `unsafe_submitted?` fails closed on that, so the
        # guard below is belt and braces for the `@form.id` read on the line after it.
        # Uploads are dropped from the stash whether they arrive bare or -- the only shape the
        # renderer produces -- as an array. They buy nothing (a file input always redisplays with
        # value=""), and they cost the session: each file serializes as junk bytes into the cookie
        # store, so a refused submission with enough attachments overflowed the 4KB cookie into a
        # 500 -- on the over-cap refusal, for exactly the visitors the refusal message is for.
        if @form.present? && fields.respond_to?(:delete_if) && !unsafe_submitted?(@form, fields)
          flash[:values] = fields.delete_if do |_k, v|
            v.instance_of?(::ActionDispatch::Http::UploadedFile) ||
              (v.is_a?(Array) && v.any?(::ActionDispatch::Http::UploadedFile))
          end
          flash[:values_form_id] = @form.id
        end
      end
    end
    if Rails::VERSION::MAJOR >= 5
      if params[:format] == 'json'
        render(json: flash.discard(:contact_form).to_hash)
      else
        redirect_back fallback_location: cama_root_path
      end
    else
      params[:format] == 'json' ? render(json: flash.discard(:contact_form).to_hash) : (redirect_to :back)
    end
  end
end
