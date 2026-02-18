# frozen_string_literal: true

class CreatePendingAgentResponses < ActiveRecord::Migration[7.1]
  def change
    create_table :pending_agent_responses do |t|
      t.references :conversation, null: false, foreign_key: true, index: true
      t.references :account, null: false, foreign_key: true, index: true
      t.references :inbox, null: false, foreign_key: true, index: true
      t.text :content, null: false
      t.string :source, null: false, default: 'agentos'
      t.references :hook, null: true, foreign_key: { to_table: :integrations_hooks }, index: true
      t.jsonb :metadata, default: {}
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :pending_agent_responses, [:conversation_id, :created_at],
              name: 'index_pending_agent_responses_on_conversation_created_at'
  end
end
