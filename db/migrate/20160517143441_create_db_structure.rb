class CreateDbStructure < ActiveRecord::Migration
  def change
    unless table_exists? 'plugins_contact_forms'
      create_table :plugins_contact_forms do |t|
        t.integer :site_id, :count, :parent_id
        t.string :name, :slug
        t.text :description, :value, :settings
        t.timestamps
      end
    end
    CamaleonCms::Site.all.each do |s|
      s.plugins.where(slug: 'contact_form').update_all(slug: 'cama_contact_form')
    end
  end
end
