Rails.application.routes.draw do

    scope PluginRoutes.system_info["relative_url_root"] do
      scope '(:locale)', locale: /#{PluginRoutes.all_locales}/, :defaults => {  } do
        # frontend
        namespace :plugins do
          namespace 'cama_contact_form' do
            post 'save_form' => "front#save_form"
          end
        end
      end

      #Admin Panel
      scope :admin, as: 'admin', path: PluginRoutes.system_info['admin_path_name'] do
        namespace 'plugins' do
          namespace 'cama_contact_form' do
            resources :admin_forms  do
              delete 'del_response'
              get 'responses'
              get 'item_field', on: :collection
            end
            get :leads, to: "admin_forms#leads"
          end
        end
      end
    end
  end
