class RemoveBodyHtmlAndBodyTextFromCampaigns < ActiveRecord::Migration[8.1]
  def change
    remove_column :campaigns, :body_html, :text
    remove_column :campaigns, :body_text, :text
  end
end
