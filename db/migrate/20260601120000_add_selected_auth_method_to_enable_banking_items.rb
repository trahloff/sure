class AddSelectedAuthMethodToEnableBankingItems < ActiveRecord::Migration[7.2]
  def change
    # Name of the Enable Banking authentication method chosen for this connection
    # (from the ASPSP's auth_methods list). Persisted so reauthorization can
    # deterministically re-select the same method instead of falling back to the
    # ASPSP default. Nullable: legacy/REDIRECT-default connections leave it blank.
    add_column :enable_banking_items, :selected_auth_method, :string
  end
end
