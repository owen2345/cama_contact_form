class RenamePluginName < ActiveRecord::Migration
  def change
    CamaleonCms::Site.all.each do |s|
      s.plugins.where(slug: 'contact_form').update_all(slug: 'cama_contact_form')
    end
  end
end
