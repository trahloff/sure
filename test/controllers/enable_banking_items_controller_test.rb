# frozen_string_literal: true

require "test_helper"
require "openssl"

class EnableBankingItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @family = families(:dylan_family)
    @item = @family.enable_banking_items.create!(
      name: "Test Connection",
      country_code: "DE",
      application_id: "test_app_id",
      client_certificate: OpenSSL::PKey::RSA.new(2048).to_pem
    )
  end

  test "select_bank exposes ASPSP BIC in the searchable data attribute" do
    Provider::EnableBanking.any_instance.stubs(:get_aspsps).returns(
      aspsps: [
        {
          name: "ING-DiBa AG",
          country: "DE",
          bic: "INGDDEFF",
          beta: false,
          psu_types: [ "personal" ],
          auth_methods: [ { approach: "REDIRECT" } ]
        }
      ]
    )

    get select_bank_enable_banking_item_url(@item)

    assert_response :success
    haystack = @response.body[/data-bank-search="([^"]*)"/, 1]
    assert haystack, "Expected list items to render a data-bank-search attribute the client filter reads from"
    assert_includes haystack, "ingddeff",
      "Expected the searchable data attribute to include the BIC so users can find banks by BIC code"
    assert_includes haystack, "ing-diba ag",
      "Expected the searchable data attribute to still include the bank name (existing name-search behavior)"
  end

  test "authorize no longer blocks decoupled banks and proceeds to the hosted auth page" do
    Provider::EnableBanking.any_instance.stubs(:get_aspsps).returns(
      aspsps: [
        {
          name: "VR Bank in Holstein",
          country: "DE",
          psu_types: [ "personal" ],
          auth_methods: [ { name: "decoupled_app", approach: "DECOUPLED" } ]
        }
      ]
    )
    Provider::EnableBanking.any_instance.stubs(:start_authorization).returns(
      url: "https://api.enablebanking.com/auth/redirect/abc",
      authorization_id: "auth_1"
    )

    post authorize_enable_banking_item_url(@item),
         params: { aspsp_name: "VR Bank in Holstein", psu_type: "personal" }

    assert_redirected_to "https://api.enablebanking.com/auth/redirect/abc"
    assert_nil flash[:alert]
    assert_equal "DECOUPLED", @item.reload.aspsp_auth_approach
    assert_equal "decoupled_app", @item.selected_auth_method
  end

  test "select_auth_method lists the bank's authentication methods" do
    Provider::EnableBanking.any_instance.stubs(:get_aspsps).returns(
      aspsps: [
        {
          name: "VR Bank in Holstein", country: "DE", bic: "GENODEF1PIN", psu_types: [ "personal" ],
          auth_methods: [
            { name: "PUSH_OTP", title: "SecureGo Plus", approach: "DECOUPLED", psu_type: "personal" },
            { name: "CHIP_OTP", title: "chipTAN", approach: "DECOUPLED", psu_type: "personal" }
          ]
        }
      ]
    )

    get select_auth_method_enable_banking_item_url(@item), params: { aspsp_name: "VR Bank in Holstein" }

    assert_response :success
    assert_match "SecureGo Plus", @response.body
    assert_match "chipTAN", @response.body
  end

  test "authorize honors the user-chosen auth_method" do
    Provider::EnableBanking.any_instance.stubs(:get_aspsps).returns(
      aspsps: [
        {
          name: "VR Bank in Holstein", country: "DE", psu_types: [ "personal" ],
          auth_methods: [
            { name: "PUSH_OTP", approach: "DECOUPLED", psu_type: "personal" },
            { name: "CHIP_OTP", approach: "DECOUPLED", psu_type: "personal" }
          ]
        }
      ]
    )
    Provider::EnableBanking.any_instance.stubs(:start_authorization).returns(
      url: "https://api.enablebanking.com/auth/redirect/xyz",
      authorization_id: "auth_2"
    )

    post authorize_enable_banking_item_url(@item),
         params: { aspsp_name: "VR Bank in Holstein", psu_type: "personal", auth_method: "CHIP_OTP" }

    assert_redirected_to "https://api.enablebanking.com/auth/redirect/xyz"
    assert_equal "CHIP_OTP", @item.reload.selected_auth_method
    assert_equal "DECOUPLED", @item.aspsp_auth_approach
  end
end
