class AddGenerateAudioToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :generate_audio, :boolean, default: true, null: false
  end
end
