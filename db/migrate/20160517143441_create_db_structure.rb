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
  end
end
