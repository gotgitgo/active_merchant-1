require 'test_helper'

class PaypalCommercePlatformTest < Test::Unit::TestCase
  include CommStub

  def setup

    @gateway     = ActiveMerchant::Billing::PaypalCommercePlatformGateway.new

    params       = user_credentials
    options      = { "Content-Type": "application/json", authorization: params }

    access_token = @gateway.get_token(options)

    @headers     = { "Authorization": access_token, "Content-Type": "application/json" }
    @body        = body

    @card_order_options = {
        "payment_source": {
            "card": {
                "name": "John Doe",
                "number": "4032039317984658",
                "expiry": "2023-07",
                "security_code": "111",
                "billing_address": {
                    "address_line_1": "12312 Port Grace Blvd",
                    "admin_area_2": "La Vista",
                    "admin_area_1": "NE",
                    "postal_code": "68128",
                    "country_code": "US"
                }
            }
        },
        "headers": @headers
    }

  end

  def test_successful_create_capture_order
    @gateway.expects(:ssl_request).times(1).returns(successful_create_capture_order_response)
    success_create_order_assertions("CAPTURE")
  end

  def test_successful_create_authorize_order
    @gateway.expects(:ssl_request).times(1).returns(successful_create_authorize_order_response)
    success_create_order_assertions("AUTHORIZE")
  end

  def test_successful_update_order
    @gateway.expects(:ssl_request).times(2).returns(successful_create_capture_order_response, successful_update_order_response)
    create = success_create_order_assertions("CAPTURE")
    order_id = create.params["id"]
    success_update_assertions(order_id)
  end

  def test_successful_create_and_capture_order
    @gateway.expects(:ssl_request).times(2).returns(successful_create_capture_order_response, successful_capture_order_response)
    create          = success_create_order_assertions("CAPTURE")
    order_id        = create.params["id"]
    success_capture_assertions(order_id)
  end

  def test_successful_create_and_authorize_order
    @gateway.expects(:ssl_request).times(2).returns(successful_create_authorize_order_response, successful_authorize_order_response)
    create          = success_create_order_assertions("AUTHORIZE")
    order_id        = create.params["id"]
    success_authorize_assertions(order_id)
  end

  def test_successful_create_and_authorize_and_capture_order
    @gateway.expects(:ssl_request).times(3).returns(successful_create_authorize_order_response, successful_authorize_order_response, successful_capture_authorized_order_response)
    create          = success_create_order_assertions("AUTHORIZE")
    order_id        = create.params["id"]
    authorize        = success_authorize_assertions(order_id)
    authorization_id = authorize.params["purchase_units"][0]["payments"]["authorizations"][0]["id"]
    success_capture_authorized_assertions(authorization_id)
  end

  def test_successful_create_and_capture_and_refund_order
    @gateway.expects(:ssl_request).times(3).returns(successful_create_capture_order_response, successful_capture_order_response, successful_refund_order_response)
    create          = success_create_order_assertions("CAPTURE")
    order_id        = create.params["id"]
    capture         = success_capture_assertions(order_id)
    capture_id      = capture.params["purchase_units"][0]["payments"]["captures"][0]["id"]
    success_refund_assertions(capture_id)
  end

  def test_successful_create_and_authorize_and_void_order
    @gateway.expects(:ssl_request).times(3).returns(successful_create_authorize_order_response, successful_authorize_order_response, successful_void_order_response)
    create           = success_create_order_assertions("AUTHORIZE")
    order_id         = create.params["id"]
    authorize        = success_authorize_assertions(order_id)
    authorization_id = authorize.params["purchase_units"][0]["payments"]["authorizations"][0]["id"]
    success_void_assertions(authorization_id)
  end

  def test_successful_create_billing_agreement_token
    @gateway.expects(:ssl_request).times(1).returns(successful_create_billing_agreement_response)
    success_create_billing_agreement_assertions
  end

  def test_successful_billing_agreement
    @gateway.expects(:ssl_request).times(1).returns(successful_approve_billing_agreement_response)
    success_approve_billing_agreement_assertions
  end

  def test_successful_capture_with_billing
    @gateway.expects(:ssl_request).times(3).returns(successful_approve_billing_agreement_response, successful_create_capture_order_response, successful_capture_with_billing_response)
    approve    = success_approve_billing_agreement_assertions
    billing_id = approve.params["id"]
    create     = success_create_order_assertions("CAPTURE")
    order_id   = create.params["id"]
    success_capture_order_with_billing_assertions(order_id, billing_id)
  end

  def test_successful_authorize_with_billing
    @gateway.expects(:ssl_request).times(3).returns(successful_approve_billing_agreement_response, successful_create_authorize_order_response, successful_authroize_with_billing_response)
    approve    = success_approve_billing_agreement_assertions
    billing_id = approve.params["id"]
    create     = success_create_order_assertions("AUTHORIZE")
    order_id   = create.params["id"]
    success_authorize_order_with_billing_assertions(order_id, billing_id)
  end

  def test_successful_cancel_billing
    @gateway.expects(:ssl_request).times(2).returns(successful_approve_billing_agreement_response, successful_cancel_billing_response)
    approve    = success_approve_billing_agreement_assertions
    billing_id = approve.params["id"]
    @body      = { note: "Cancelling Subscription" }
    response   = @gateway.cancel_billing_agreement(billing_id, options)
    assert_success response
  end

  def test_failed_update_order_business_validation_error
    @gateway.expects(:ssl_request).times(2).returns(successful_create_capture_order_response, failed_update_order_due_to_business_error_response)
    create = success_create_order_assertions("CAPTURE")
    order_id = create.params["id"]
    failed_update_assertions(order_id)
  end

  def test_failed_cancel_billing_after_approval
    @gateway.expects(:ssl_request).times(2).returns(successful_approve_billing_agreement_response, failed_cancel_billing_due_to_business_error)
    approve    = success_approve_billing_agreement_assertions
    billing_id = approve.params["id"]
    @body      = { note: "Cancelling Subscription" }
    response   = @gateway.cancel_billing_agreement(billing_id, options)
    assert_failure response
    assert_equal "BUSINESS_ERROR", response.params["name"]
    assert_equal "Business error", response.params["message"]
  end

  def test_failed_create_capture_order_due_to_invalid_schema
    @gateway.expects(:ssl_request).times(1).returns(failed_create_order_invalid_schema_response)
    failed_create_order_invalid_schema_assertions
  end

  def test_failed_create_capture_order_due_to_invalid_business_validation
    @gateway.expects(:ssl_request).times(1).returns(failed_create_order_invalid_business_validation_response)
    failed_create_order_invalid_business_validation_assertions
  end

  def test_failed_capture_after_creation_due_to_invalid_schema(order_id)
    @gateway.expects(:ssl_request).times(2).returns(successful_create_capture_order_response, failed_capture_order_invalid_schema_response)
    create          = success_create_order_assertions("CAPTURE")
    order_id        = create.params["id"]
    failed_capture_order_invalid_schema_assertions(order_id)
  end

  def test_failed_capture_after_creation_due_to_invalid_business_validation
    @gateway.expects(:ssl_request).times(2).returns(successful_create_capture_order_response, failed_capture_order_invalid_business_validation_response)
    create          = success_create_order_assertions("CAPTURE")
    order_id        = create.params["id"]
    failed_capture_order_invalid_business_validation_assertions(order_id)
  end

  def test_failed_authorize_after_creation_due_to_invalid_schema
    @gateway.expects(:ssl_request).times(2).returns(successful_create_capture_order_response, failed_authorize_order_invalid_schema_response)
    create          = success_create_order_assertions("CAPTURE")
    order_id        = create.params["id"]
    failed_authorize_order_invalid_schema_assertions(order_id)
  end

  def test_failed_authorize_after_creation_due_to_invalid_business_validations
    @gateway.expects(:ssl_request).times(2).returns(successful_create_authorize_order_response, failed_authorize_order_invalid_business_validation_response)
    create          = success_create_order_assertions("AUTHORIZE")
    order_id        = create.params["id"]
    failed_authorize_order_invalid_business_validation_assertions(order_id)
  end

  def test_failed_void_due_to_invalid_resource
    @gateway.expects(:ssl_request).times(1).returns(failed_void_invalid_resource_response)
    failed_void_invalid_resource_assertions
  end

  def test_failed_void_due_to_invalid_business_validation
    @gateway.expects(:ssl_request).times(3).returns(successful_create_authorize_order_response, successful_authorize_order_response, failed_void_invalid_business_validation_response)
    create           = success_create_order_assertions("AUTHORIZE")
    order_id         = create.params["id"]
    authorize        = success_authorize_assertions(order_id)
    authorization_id = authorize.params["purchase_units"][0]["payments"]["authorizations"][0]["id"]
    failed_void_invalid_business_validation_assertions(authorization_id)
  end

  def test_failed_refund_due_to_invalid_schema
    @gateway.expects(:ssl_request).times(3).returns(successful_create_capture_order_response, successful_capture_order_response, failed_refund_invalid_schema_response)
    create           = success_create_order_assertions("CAPTURE")
    order_id         = create.params["id"]
    capture         = success_capture_assertions(order_id)
    capture_id      = capture.params["purchase_units"][0]["payments"]["captures"][0]["id"]
    failed_refund_invalid_schema_assertions(capture_id)
  end

  def test_failed_refund_due_to_invalid_business_validation
    @gateway.expects(:ssl_request).times(3).returns(successful_create_capture_order_response, successful_capture_order_response, failed_refund_invalid_business_validation_response)
    create           = success_create_order_assertions("CAPTURE")
    order_id         = create.params["id"]
    capture         = success_capture_assertions(order_id)
    capture_id      = capture.params["purchase_units"][0]["payments"]["captures"][0]["id"]
    failed_refund_invalid_business_validation_assertions(capture_id)
  end

  private

  def successful_create_capture_order_response
    <<-RESPONSE
    {
        "id": "9BT77635MT4641640",
        "intent": "CAPTURE",
        "status": "CREATED",
        "purchase_units": [
            {
                "reference_id": "camera_shop_seller_1600688584",
                "amount": {
                    "currency_code": "USD",
                    "value": "25.00",
                    "breakdown": {
                        "item_total": {
                            "currency_code": "USD",
                            "value": "25.00"
                        },
                        "shipping": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "handling": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "tax_total": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "shipping_discount": {
                            "currency_code": "USD",
                            "value": "0.00"
                        }
                    }
                },
                "payee": {
                    "merchant_id": "3WK2L2WM58FGJ"
                },
                "payment_instruction": {
                    "platform_fees": [
                        {
                            "amount": {
                                "currency_code": "USD",
                                "value": "2.00"
                            },
                            "payee": {
                                "email_address": "sb-jnxjj3033194@business.example.com"
                            }
                        }
                    ]
                },
                "description": "Camera Shop",
                "custom_id": "custom_value_1600688584",
                "invoice_id": "invoice_number_1600688584",
                "soft_descriptor": "Payment Camera Shop",
                "items": [
                    {
                        "name": "Levis 501 Selvedge STF",
                        "unit_amount": {
                            "currency_code": "USD",
                            "value": "25.00"
                        },
                        "tax": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "quantity": "1",
                        "sku": "5158936",
                        "category": "PHYSICAL_GOODS"
                    }
                ],
                "shipping": {
                    "address": {
                        "address_line_1": "500 Hillside Street",
                        "address_line_2": "#1000",
                        "admin_area_2": "San Jose",
                        "admin_area_1": "CA",
                        "postal_code": "95131",
                        "country_code": "US"
                    }
                }
            }
        ],
        "create_time": "2020-09-21T11:43:18Z",
        "links": [
            {
                "href": "https://api.sandbox.paypal.com/v2/checkout/orders/9BT77635MT4641640",
                "rel": "self",
                "method": "GET"
            },
            {
                "href": "https://www.sandbox.paypal.com/checkoutnow?token=9BT77635MT4641640",
                "rel": "approve",
                "method": "GET"
            },
            {
                "href": "https://api.sandbox.paypal.com/v2/checkout/orders/9BT77635MT4641640",
                "rel": "update",
                "method": "PATCH"
            },
            {
                "href": "https://api.sandbox.paypal.com/v2/checkout/orders/9BT77635MT4641640/capture",
                "rel": "capture",
                "method": "POST"
            }
        ]
    }
    RESPONSE
  end

  def successful_create_authorize_order_response
    <<-RESPONSE
    {
        "id": "4JH59093WW6700247",
        "intent": "AUTHORIZE",
        "status": "CREATED",
        "purchase_units": [
            {
                "reference_id": "camera_shop_seller_1600759551",
                "amount": {
                    "currency_code": "USD",
                    "value": "25.00",
                    "breakdown": {
                        "item_total": {
                            "currency_code": "USD",
                            "value": "25.00"
                        },
                        "shipping": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "handling": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "tax_total": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "shipping_discount": {
                            "currency_code": "USD",
                            "value": "0.00"
                        }
                    }
                },
                "payee": {
                    "merchant_id": "3WK2L2WM58FGJ"
                },
                "description": "Camera Shop",
                "custom_id": "custom_value_1600759551",
                "invoice_id": "invoice_number_1600759551",
                "soft_descriptor": "Payment Camera Shop",
                "items": [
                    {
                        "name": "Levis 501 Selvedge STF",
                        "unit_amount": {
                            "currency_code": "USD",
                            "value": "25.00"
                        },
                        "tax": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "quantity": "1",
                        "sku": "5158936",
                        "category": "PHYSICAL_GOODS"
                    }
                ],
                "shipping": {
                    "address": {
                        "address_line_1": "500 Hillside Street",
                        "address_line_2": "#1000",
                        "admin_area_2": "San Jose",
                        "admin_area_1": "CA",
                        "postal_code": "95131",
                        "country_code": "US"
                    }
                }
            }
        ],
        "create_time": "2020-09-22T07:26:05Z",
        "links": [
            {
                "href": "https://api.sandbox.paypal.com/v2/checkout/orders/4JH59093WW6700247",
                "rel": "self",
                "method": "GET"
            },
            {
                "href": "https://www.sandbox.paypal.com/checkoutnow?token=4JH59093WW6700247",
                "rel": "approve",
                "method": "GET"
            },
            {
                "href": "https://api.sandbox.paypal.com/v2/checkout/orders/4JH59093WW6700247",
                "rel": "update",
                "method": "PATCH"
            },
            {
                "href": "https://api.sandbox.paypal.com/v2/checkout/orders/4JH59093WW6700247/authorize",
                "rel": "authorize",
                "method": "POST"
            }
        ]
    }
    RESPONSE
  end


  def successful_update_order_response
    <<-RESPONSE
    {
    }
    RESPONSE
  end

  def successful_capture_order_response
    <<-RESPONSE
     {
        "id": "4PB35597VW646211S",
        "intent": "CAPTURE",
        "status": "COMPLETED",
        "payment_source": {
            "card": {
                "last_digits": "4658",
                "brand": "VISA",
                "type": "CREDIT"
            }
        },
        "purchase_units": [
            {
                "reference_id": "camera_shop_seller_1600760302",
                "amount": {
                    "currency_code": "USD",
                    "value": "25.00",
                    "breakdown": {
                        "item_total": {
                            "currency_code": "USD",
                            "value": "25.00"
                        },
                        "shipping": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "handling": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "tax_total": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "insurance": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "shipping_discount": {
                            "currency_code": "USD",
                            "value": "0.00"
                        }
                    }
                },
                "payee": {
                    "email_address": "sb-for7q2968277@personal.example.com",
                    "merchant_id": "3WK2L2WM58FGJ"
                },
                "payment_instruction": {
                    "platform_fees": [
                        {
                            "amount": {
                                "currency_code": "USD",
                                "value": "2.00"
                            }
                        }
                    ]
                },
                "description": "Camera Shop",
                "custom_id": "custom_value_1600760302",
                "invoice_id": "invoice_number_1600760302",
                "soft_descriptor": "PP*Payment Camera Shop",
                "items": [
                    {
                        "name": "Levis 501 Selvedge STF",
                        "unit_amount": {
                            "currency_code": "USD",
                            "value": "25.00"
                        },
                        "tax": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "quantity": "1",
                        "sku": "5158936"
                    }
                ],
                "shipping": {
                    "address": {
                        "address_line_1": "500 Hillside Street",
                        "address_line_2": "#1000",
                        "admin_area_2": "San Jose",
                        "admin_area_1": "CA",
                        "postal_code": "95131",
                        "country_code": "US"
                    }
                },
                "payments": {
                    "captures": [
                        {
                            "id": "99B31255NY205423M",
                            "status": "COMPLETED",
                            "amount": {
                                "currency_code": "USD",
                                "value": "25.00"
                            },
                            "final_capture": true,
                            "disbursement_mode": "INSTANT",
                            "seller_protection": {
                                "status": "NOT_ELIGIBLE"
                            },
                            "seller_receivable_breakdown": {
                                "gross_amount": {
                                    "currency_code": "USD",
                                    "value": "25.00"
                                },
                                "paypal_fee": {
                                    "currency_code": "USD",
                                    "value": "1.03"
                                },
                                "net_amount": {
                                    "currency_code": "USD",
                                    "value": "23.97"
                                }
                            },
                            "invoice_id": "invoice_number_1600760302",
                            "custom_id": "custom_value_1600760302",
                            "links": [
                                {
                                    "href": "https://api.sandbox.paypal.com/v2/payments/captures/99B31255NY205423M",
                                    "rel": "self",
                                    "method": "GET"
                                },
                                {
                                    "href": "https://api.sandbox.paypal.com/v2/payments/captures/99B31255NY205423M/refund",
                                    "rel": "refund",
                                    "method": "POST"
                                },
                                {
                                    "href": "https://api.sandbox.paypal.com/v2/checkout/orders/4PB35597VW646211S",
                                    "rel": "up",
                                    "method": "GET"
                                }
                            ],
                            "create_time": "2020-09-22T07:38:47Z",
                            "update_time": "2020-09-22T07:38:47Z",
                            "processor_response": {
                                "avs_code": "A",
                                "cvv_code": "M",
                                "response_code": "0000"
                            }
                        }
                    ]
                }
            }
        ],
        "create_time": "2020-09-22T07:38:47Z",
        "update_time": "2020-09-22T07:38:47Z",
        "links": [
            {
                "href": "https://api.sandbox.paypal.com/v2/checkout/orders/4PB35597VW646211S",
                "rel": "self",
                "method": "GET"
            }
        ]
    }
    RESPONSE
  end

  def successful_authorize_order_response
    <<-RESPONSE
    {
        "id": "0UX88842XW347023K",
        "intent": "AUTHORIZE",
        "status": "COMPLETED",
        "payment_source": {
            "card": {
                "last_digits": "4658",
                "brand": "VISA",
                "type": "CREDIT"
            }
        },
        "purchase_units": [
            {
                "reference_id": "camera_shop_seller_1600761634",
                "amount": {
                    "currency_code": "USD",
                    "value": "25.00",
                    "breakdown": {
                        "item_total": {
                            "currency_code": "USD",
                            "value": "25.00"
                        },
                        "shipping": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "handling": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "tax_total": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "insurance": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "shipping_discount": {
                            "currency_code": "USD",
                            "value": "0.00"
                        }
                    }
                },
                "payee": {
                    "email_address": "sb-jnxjj3033194@business.example.com",
                    "merchant_id": "XC424JYN8FYUC"
                },
                "description": "Camera Shop",
                "custom_id": "custom_value_1600761634",
                "invoice_id": "invoice_number_1600761634",
                "soft_descriptor": "PP*Payment Camera Shop",
                "items": [
                    {
                        "name": "Levis 501 Selvedge STF",
                        "unit_amount": {
                            "currency_code": "USD",
                            "value": "25.00"
                        },
                        "tax": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "quantity": "1",
                        "sku": "5158936"
                    }
                ],
                "shipping": {
                    "address": {
                        "address_line_1": "500 Hillside Street",
                        "address_line_2": "#1000",
                        "admin_area_2": "San Jose",
                        "admin_area_1": "CA",
                        "postal_code": "95131",
                        "country_code": "US"
                    }
                },
                "payments": {
                    "authorizations": [
                        {
                            "status": "CREATED",
                            "id": "8SA13118FD156945S",
                            "amount": {
                                "currency_code": "USD",
                                "value": "25.00"
                            },
                            "invoice_id": "invoice_number_1600761634",
                            "custom_id": "custom_value_1600761634",
                            "seller_protection": {
                                "status": "NOT_ELIGIBLE"
                            },
                            "processor_response": {
                                "avs_code": "A",
                                "cvv_code": "M",
                                "response_code": "0000"
                            },
                            "expiration_time": "2020-10-21T08:03:10Z",
                            "links": [
                                {
                                    "href": "https://api.sandbox.paypal.com/v2/payments/authorizations/8SA13118FD156945S",
                                    "rel": "self",
                                    "method": "GET"
                                },
                                {
                                    "href": "https://api.sandbox.paypal.com/v2/payments/authorizations/8SA13118FD156945S/capture",
                                    "rel": "capture",
                                    "method": "POST"
                                },
                                {
                                    "href": "https://api.sandbox.paypal.com/v2/payments/authorizations/8SA13118FD156945S/void",
                                    "rel": "void",
                                    "method": "POST"
                                },
                                {
                                    "href": "https://api.sandbox.paypal.com/v2/payments/authorizations/8SA13118FD156945S/reauthorize",
                                    "rel": "reauthorize",
                                    "method": "POST"
                                },
                                {
                                    "href": "https://api.sandbox.paypal.com/v2/checkout/orders/0UX88842XW347023K",
                                    "rel": "up",
                                    "method": "GET"
                                }
                            ],
                            "create_time": "2020-09-22T08:03:10Z",
                            "update_time": "2020-09-22T08:03:10Z"
                        }
                    ]
                }
            }
        ],
        "create_time": "2020-09-22T08:03:10Z",
        "update_time": "2020-09-22T08:03:10Z",
        "links": [
            {
                "href": "https://api.sandbox.paypal.com/v2/checkout/orders/0UX88842XW347023K",
                "rel": "self",
                "method": "GET"
            }
        ]
    }
    RESPONSE
  end

  def successful_capture_authorized_order_response
    <<-RESPONSE
    {
        "id": "2K5804563Y769942W",
        "amount": {
            "currency_code": "USD",
            "value": "25.00"
        },
        "final_capture": true,
        "seller_protection": {
            "status": "NOT_ELIGIBLE"
        },
        "seller_receivable_breakdown": {
            "gross_amount": {
                "currency_code": "USD",
                "value": "25.00"
            },
            "paypal_fee": {
                "currency_code": "USD",
                "value": "1.03"
            },
            "net_amount": {
                "currency_code": "USD",
                "value": "23.97"
            },
            "exchange_rate": {}
        },
        "invoice_id": "invoice_number_1600770880",
        "custom_id": "custom_value_1600770880",
        "status": "COMPLETED",
        "create_time": "2020-09-22T10:35:22Z",
        "update_time": "2020-09-22T10:35:22Z",
        "links": [
            {
                "href": "https://api.sandbox.paypal.com/v2/payments/captures/2K5804563Y769942W",
                "rel": "self",
                "method": "GET"
            },
            {
                "href": "https://api.sandbox.paypal.com/v2/payments/captures/2K5804563Y769942W/refund",
                "rel": "refund",
                "method": "POST"
            },
            {
                "href": "https://api.sandbox.paypal.com/v2/payments/authorizations/6FR70621P6086464T",
                "rel": "up",
                "method": "GET"
            }
        ]
    }
    RESPONSE
  end

  def successful_refund_order_response
    <<-RESPONSE
    {
        "id": "90E25538TL390384X",
        "status": "COMPLETED",
        "links": [
            {
                "href": "https://api.sandbox.paypal.com/v2/payments/refunds/90E25538TL390384X",
                "rel": "self",
                "method": "GET"
            },
            {
                "href": "https://api.sandbox.paypal.com/v2/payments/captures/00U22118MH8302016",
                "rel": "up",
                "method": "GET"
            }
        ]
    }
    RESPONSE
  end

  def successful_void_order_response
    <<-RESPONSE
    {}
    RESPONSE
  end

  def successful_create_billing_agreement_response
    <<-RESPONSE
    {
        "links": [
            {
                "href": "https://www.sandbox.paypal.com/agreements/approve?ba_token=BA-90Y76158PD2562838",
                "rel": "approval_url",
                "method": "POST"
            },
            {
                "href": "https://api.sandbox.paypal.com/v1/billing-agreements/BA-90Y76158PD2562838/agreements",
                "rel": "self",
                "method": "POST"
            }
        ],
        "token_id": "BA-90Y76158PD2562838"
    }
    RESPONSE
  end

  def successful_approve_billing_agreement_response
    <<-RESPONSE
    {
        "id": "B-0WH24593LA6945220",
        "state": "ACTIVE",
        "description": "Billing Agreement",
        "payer": {
            "payer_info": {
                "email": "sb-feqsa3029697@personal.example.com",
                "first_name": "John",
                "last_name": "Doe",
                "payer_id": "DWUPFA2VU2W9E",
                "billing_address": {
                    "line1": "1 Main St",
                    "city": "San Jose",
                    "state": "CA",
                    "postal_code": "95131",
                    "country_code": "US"
                }
            }
        },
        "shipping_address": {
            "recipient_name": "John Doe",
            "line1": "1350 North First Street",
            "city": "San Jose",
            "state": "CA",
            "postal_code": "95112",
            "country_code": "US"
        },
        "plan": {
            "type": "MERCHANT_INITIATED_BILLING",
            "merchant_preferences": {
                "accepted_pymt_type": "INSTANT"
            }
        },
        "create_time": "2020-09-22T14:57:28.000Z",
        "update_time": "2020-09-22T14:57:28.000Z",
        "links": [
            {
                "href": "https://api.sandbox.paypal.com/v1/billing-agreements/agreements/B-0WH24593LA6945220/cancel",
                "rel": "cancel",
                "method": "POST"
            },
            {
                "href": "https://api.sandbox.paypal.com/v1/billing-agreements/agreements/B-0WH24593LA6945220",
                "rel": "self",
                "method": "GET"
            }
        ],
        "merchant": {
            "payee_info": {
                "email": "sb-jnxjj3033194@business.example.com"
            }
        }
    }
    RESPONSE
  end

  def successful_capture_with_billing_response
    <<-RESPONSE
        {
        "id": "2GX9446699622573N",
        "intent": "CAPTURE",
        "status": "COMPLETED",
        "purchase_units": [
            {
                "reference_id": "camera_shop_seller_1600788267",
                "amount": {
                    "currency_code": "USD",
                    "value": "60.00"
                },
                "payee": {
                    "email_address": "sb-jnxjj3033194@business.example.com",
                    "merchant_id": "XC424JYN8FYUC"
                },
                "payments": {
                    "captures": [
                        {
                            "id": "2B82960192651640F",
                            "status": "COMPLETED",
                            "amount": {
                                "currency_code": "USD",
                                "value": "60.00"
                            },
                            "final_capture": true,
                            "seller_protection": {
                                "status": "ELIGIBLE",
                                "dispute_categories": [
                                    "ITEM_NOT_RECEIVED",
                                    "UNAUTHORIZED_TRANSACTION"
                                ]
                            },
                            "seller_receivable_breakdown": {
                                "gross_amount": {
                                    "currency_code": "USD",
                                    "value": "60.00"
                                },
                                "paypal_fee": {
                                    "currency_code": "USD",
                                    "value": "2.04"
                                },
                                "net_amount": {
                                    "currency_code": "USD",
                                    "value": "57.96"
                                }
                            },
                            "links": [
                                {
                                    "href": "https://api.sandbox.paypal.com/v2/payments/captures/2B82960192651640F",
                                    "rel": "self",
                                    "method": "GET"
                                },
                                {
                                    "href": "https://api.sandbox.paypal.com/v2/payments/captures/2B82960192651640F/refund",
                                    "rel": "refund",
                                    "method": "POST"
                                },
                                {
                                    "href": "https://api.sandbox.paypal.com/v2/checkout/orders/2GX9446699622573N",
                                    "rel": "up",
                                    "method": "GET"
                                }
                            ],
                            "create_time": "2020-09-22T15:24:47Z",
                            "update_time": "2020-09-22T15:24:47Z"
                        }
                    ]
                }
            }
        ],
        "payer": {
            "name": {
                "given_name": "John",
                "surname": "Doe"
            },
            "email_address": "sb-feqsa3029697@personal.example.com",
            "payer_id": "DWUPFA2VU2W9E",
            "address": {
                "address_line_1": "1 Main St",
                "admin_area_2": "San Jose",
                "admin_area_1": "CA",
                "postal_code": "95131",
                "country_code": "US"
            }
        },
        "create_time": "2020-09-22T15:24:40Z",
        "update_time": "2020-09-22T15:24:47Z",
        "links": [
            {
                "href": "https://api.sandbox.paypal.com/v2/checkout/orders/2GX9446699622573N",
                "rel": "self",
                "method": "GET"
            }
        ]
    }
    RESPONSE
  end

  def successful_cancel_billing_response
    <<-RESPONSE
    RESPONSE
  end

  def successful_authroize_with_billing_response
    <<-RESPONSE
    {
        "id": "1GM23777922690625",
        "intent": "AUTHORIZE",
        "status": "COMPLETED",
        "purchase_units": [
            {
                "reference_id": "camera_shop_seller_1600788653",
                "amount": {
                    "currency_code": "USD",
                    "value": "25.00",
                    "breakdown": {
                        "item_total": {
                            "currency_code": "USD",
                            "value": "25.00"
                        },
                        "shipping": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "handling": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "tax_total": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "insurance": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "shipping_discount": {
                            "currency_code": "USD",
                            "value": "0.00"
                        }
                    }
                },
                "payee": {
                    "email_address": "sb-for7q2968277@personal.example.com",
                    "merchant_id": "3WK2L2WM58FGJ"
                },
                "description": "Camera Shop",
                "custom_id": "custom_value_1600788653",
                "invoice_id": "invoice_number_1600788653",
                "items": [
                    {
                        "name": "Levis 501 Selvedge STF",
                        "unit_amount": {
                            "currency_code": "USD",
                            "value": "25.00"
                        },
                        "tax": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "quantity": "1",
                        "sku": "5158936"
                    }
                ],
                "shipping": {
                    "name": {
                        "full_name": "John Doe"
                    },
                    "address": {
                        "address_line_1": "500 Hillside Street",
                        "address_line_2": "#1000",
                        "admin_area_2": "San Jose",
                        "admin_area_1": "CA",
                        "postal_code": "95131",
                        "country_code": "US"
                    }
                },
                "payments": {
                    "authorizations": [
                        {
                            "status": "CREATED",
                            "id": "3RF97879M2824560N",
                            "amount": {
                                "currency_code": "USD",
                                "value": "25.00"
                            },
                            "invoice_id": "invoice_number_1600788653",
                            "custom_id": "custom_value_1600788653",
                            "seller_protection": {
                                "status": "ELIGIBLE",
                                "dispute_categories": [
                                    "ITEM_NOT_RECEIVED",
                                    "UNAUTHORIZED_TRANSACTION"
                                ]
                            },
                            "expiration_time": "2020-10-21T15:31:13Z",
                            "links": [
                                {
                                    "href": "https://api.sandbox.paypal.com/v2/payments/authorizations/3RF97879M2824560N",
                                    "rel": "self",
                                    "method": "GET"
                                },
                                {
                                    "href": "https://api.sandbox.paypal.com/v2/payments/authorizations/3RF97879M2824560N/capture",
                                    "rel": "capture",
                                    "method": "POST"
                                },
                                {
                                    "href": "https://api.sandbox.paypal.com/v2/payments/authorizations/3RF97879M2824560N/void",
                                    "rel": "void",
                                    "method": "POST"
                                },
                                {
                                    "href": "https://api.sandbox.paypal.com/v2/payments/authorizations/3RF97879M2824560N/reauthorize",
                                    "rel": "reauthorize",
                                    "method": "POST"
                                },
                                {
                                    "href": "https://api.sandbox.paypal.com/v2/checkout/orders/1GM23777922690625",
                                    "rel": "up",
                                    "method": "GET"
                                }
                            ],
                            "create_time": "2020-09-22T15:31:13Z",
                            "update_time": "2020-09-22T15:31:13Z"
                        }
                    ]
                }
            }
        ],
        "payer": {
            "name": {
                "given_name": "John",
                "surname": "Doe"
            },
            "email_address": "sb-feqsa3029697@personal.example.com",
            "payer_id": "DWUPFA2VU2W9E",
            "address": {
                "address_line_1": "1 Main St",
                "admin_area_2": "San Jose",
                "admin_area_1": "CA",
                "postal_code": "95131",
                "country_code": "US"
            }
        },
        "create_time": "2020-09-22T15:31:06Z",
        "update_time": "2020-09-22T15:31:13Z",
        "links": [
            {
                "href": "https://api.sandbox.paypal.com/v2/checkout/orders/1GM23777922690625",
                "rel": "self",
                "method": "GET"
            }
        ]
    }
    RESPONSE
  end

  def failed_update_order_due_to_business_error_response
    <<-RESPONSE
    {
        "name": "UNPROCESSABLE_ENTITY",
        "details": [
            {
                "field": "path",
                "value": "/purchase_units/0/XYZ",
                "location": "body",
                "issue": "INVALID_PARAMETER",
                "description": "Cannot be specified as part of the request."
            }
        ],
        "message": "The requested action could not be performed, semantically incorrect, or failed business validation.",
        "debug_id": "c6adfcf430574",
        "links": [
            {
                "href": "https://developer.paypal.com/docs/api/orders/v2/#error-INVALID_PARAMETER",
                "rel": "information_link",
                "method": "GET"
            }
        ]
    }
    RESPONSE
  end

  def failed_cancel_billing_due_to_business_error
    <<-RESPONSE
    {
        "name": "BUSINESS_ERROR",
        "debug_id": "4bda83f5f8f42",
        "message": "Business error",
        "information_link": "https://developer.paypal.com/webapps/developer/docs/api/#BUSINESS_ERROR",
        "details": [
            {
                "name": "RT_AGREEMENT_ALREADY_CANCELED",
                "message": "Failed Request: Agreement is already cancelled / Invalid agreement state"
            }
        ]
    }
    RESPONSE
  end

  def failed_create_order_invalid_schema_response
    <<-RESPONSE
    {
        "name": "INVALID_REQUEST",
        "message": "Request is not well-formed, syntactically incorrect, or violates schema.",
        "debug_id": "adcf063fa5872",
        "details": [
            {
                "field": "/intent",
                "value": "",
                "location": "body",
                "issue": "MISSING_REQUIRED_PARAMETER",
                "description": "A required field / parameter is missing."
            }
        ],
        "links": [
            {
                "href": "https://developer.paypal.com/docs/api/orders/v2/#error-MISSING_REQUIRED_PARAMETER",
                "rel": "information_link",
                "encType": "application/json"
            }
        ]
    }
    RESPONSE
  end

  def failed_create_order_invalid_business_validation_response
    <<-RESPONSE
    {
        "name": "UNPROCESSABLE_ENTITY",
        "details": [
            {
                "field": "/purchase_units/@reference_id=='camera_shop_seller_1600766405'/amount/value",
                "value": "-1.00",
                "issue": "CANNOT_BE_ZERO_OR_NEGATIVE",
                "description": "Must be greater than zero. If the currency supports decimals, only two decimal place precision is supported."
            }
        ],
        "message": "The requested action could not be performed, semantically incorrect, or failed business validation.",
        "debug_id": "82f067edbb566",
        "links": [
            {
                "href": "https://developer.paypal.com/docs/api/orders/v2/#error-CANNOT_BE_ZERO_OR_NEGATIVE",
                "rel": "information_link",
                "method": "GET"
            }
        ]
    }
    RESPONSE
  end

  def failed_capture_order_invalid_schema_response
    <<-RESPONSE
    {
        "name": "INVALID_REQUEST",
        "message": "Request is not well-formed, syntactically incorrect, or violates schema.",
        "debug_id": "904aa793bcf15",
        "details": [
            {
                "field": "/payment_source/card/number",
                "value": "",
                "location": "body",
                "issue": "MISSING_REQUIRED_PARAMETER",
                "description": "A required field / parameter is missing."
            }
        ],
        "links": [
            {
                "href": "https://developer.paypal.com/docs/api/orders/v2/#error-MISSING_REQUIRED_PARAMETER",
                "rel": "information_link",
                "encType": "application/json"
            }
        ]
    }
    RESPONSE
  end

  def failed_capture_order_invalid_business_validation_response
    <<-RESPONSE
      {
        "name": "UNPROCESSABLE_ENTITY",
        "details": [
            {
                "issue": "ORDER_ALREADY_CAPTURED",
                "description": "Order already captured.If 'intent=CAPTURE' only one capture per order is allowed."
            }
        ],
        "message": "The requested action could not be performed, semantically incorrect, or failed business validation.",
        "debug_id": "001e3a7caa573",
        "links": [
            {
                "href": "https://developer.paypal.com/docs/api/orders/v2/#error-ORDER_ALREADY_CAPTURED",
                "rel": "information_link",
                "method": "GET"
            }
        ]
    }
    RESPONSE
  end

  def failed_authorize_order_invalid_business_validation_response
    <<-RESPONSE
    {
        "name": "UNPROCESSABLE_ENTITY",
        "details": [
            {
                "issue": "DUPLICATE_INVOICE_ID",
                "description": "Duplicate Invoice ID detected. To avoid a potential duplicate transaction your account setting requires that Invoice Id be unique for each transaction."
            }
        ],
        "message": "The requested action could not be performed, semantically incorrect, or failed business validation.",
        "debug_id": "8ec6eb09c6906",
        "links": [
            {
                "href": "https://developer.paypal.com/docs/api/orders/v2/#error-DUPLICATE_INVOICE_ID",
                "rel": "information_link",
                "method": "GET"
            }
        ]
    }
    RESPONSE
  end

  def failed_authorize_order_invalid_schema_response
    <<-RESPONSE
    {
        "name": "INVALID_REQUEST",
        "message": "Request is not well-formed, syntactically incorrect, or violates schema.",
        "debug_id": "82092f4b2e382",
        "details": [
            {
                "field": "/payment_source/card/number",
                "value": "",
                "location": "body",
                "issue": "MISSING_REQUIRED_PARAMETER",
                "description": "A required field / parameter is missing."
            }
        ],
        "links": [
            {
                "href": "https://developer.paypal.com/docs/api/orders/v2/#error-MISSING_REQUIRED_PARAMETER",
                "rel": "information_link",
                "encType": "application/json"
            }
        ]
    }
    RESPONSE
  end

  def failed_void_invalid_resource_response
    <<-RESPONSE
    {
        "name": "RESOURCE_NOT_FOUND",
        "message": "The specified resource does not exist.",
        "debug_id": "16604b09b8cf7",
        "details": [
            {
                "issue": "INVALID_RESOURCE_ID",
                "field": "authorization_id",
                "value": "123",
                "description": "Specified resource ID does not exist. Please check the resource ID and try again.",
                "location": "path"
            }
        ],
        "links": [
            {
                "href": "https://developer.paypal.com/docs/api/payments/v2/#error-INVALID_RESOURCE_ID",
                "rel": "information_link"
            }
        ]
    }
    RESPONSE
  end

  def failed_void_invalid_business_validation_response
    <<-RESPONSE
    {
        "name": "UNPROCESSABLE_ENTITY",
        "message": "The requested action could not be performed, semantically incorrect, or failed business validation.",
        "debug_id": "a50e8cc9962e0",
        "details": [
            {
                "issue": "PREVIOUSLY_VOIDED",
                "description": "Authorization has been previously voided and hence cannot be voided again."
            }
        ],
        "links": [
            {
                "href": "https://developer.paypal.com/docs/api/payments/v2/#error-PREVIOUSLY_VOIDED",
                "rel": "information_link"
            }
        ]
    }
    RESPONSE
  end

  def failed_refund_invalid_business_validation_response
    <<-RESPONSE
    {
        "name": "UNPROCESSABLE_ENTITY",
        "message": "The requested action could not be performed, semantically incorrect, or failed business validation.",
        "debug_id": "3db37b636c47c",
        "details": [
            {
                "issue": "CANNOT_BE_ZERO_OR_NEGATIVE",
                "field": "/amount/value",
                "value": "-13",
                "description": "The value of the field should be greater than zero.",
                "location": "body"
            }
        ],
        "links": [
            {
                "href": "https://developer.paypal.com/docs/api/payments/v2/#error-CANNOT_BE_ZERO_OR_NEGATIVE",
                "rel": "information_link"
            }
        ]
    }
    RESPONSE
  end

  def failed_refund_invalid_schema_response
    <<-RESPONSE
    {
        "name": "INVALID_REQUEST",
        "message": "Request is not well-formed, syntactically incorrect, or violates schema",
        "debug_id": "8c62076187d7a",
        "details": [
            {
                "issue": "MISSING_REQUIRED_PARAMETER",
                "field": "/amount/currency_code",
                "value": "",
                "description": "A required field/parameter is missing",
                "location": "body"
            }
        ],
        "links": [
            {
                "href": "https://developer.paypal.com/docs/api/payments/v2/#error-MISSING_REQUIRED_PARAMETER",
                "rel": "information_link"
            }
        ]
    }
    RESPONSE
  end

  def body
    @reference_id = "camera_shop_seller_#{ DateTime.now }"

    {
        "intent": "CAPTURE",
        "purchase_units": [
            {
                "reference_id": @reference_id,
                "description": "Camera Shop",
                "amount": {
                    "currency_code": "USD",
                    "value": "25.00",
                    "breakdown": {
                        "item_total": {
                            "currency_code": "USD",
                            "value": "25.00"
                        },
                        "shipping": {
                            "currency_code": "USD",
                            "value": "0"
                        },
                        "handling": {
                            "currency_code": "USD",
                            "value": "0"
                        },
                        "tax_total": {
                            "currency_code": "USD",
                            "value": "0"
                        },
                        "gift_wrap": {
                            "currency_code": "USD",
                            "value": "0"
                        },
                        "shipping_discount": {
                            "currency_code": "USD",
                            "value": "0"
                        }
                    }
                },
                "payee": {
                    "email_address": "sb-jnxjj3033194@business.example.com"
                },
                "items": [
                    {
                        "name": "Levis 501 Selvedge STF",
                        "sku": "5158936",
                        "unit_amount": {
                            "currency_code": "USD",
                            "value": "25.00"
                        },
                        "tax": {
                            "currency_code": "USD",
                            "value": "0.00"
                        },
                        "quantity": "1",
                        "category": "PHYSICAL_GOODS"
                    }
                ],
                "shipping": {
                    "address": {
                        "address_line_1": "500 Hillside Street",
                        "address_line_2": "#1000",
                        "admin_area_1": "CA",
                        "admin_area_2": "San Jose",
                        "postal_code": "95131",
                        "country_code": "US"
                    }
                },
                "shipping_method": "United Postal Service",
                "payment_group_id": 1,
                "custom_id": "custom_value_#{ DateTime.now }",
                "invoice_id": "invoice_number_#{ DateTime.now }",
                "soft_descriptor": "Payment Camera Shop"
            }
        ],
        "application_context": {
            "return_url": "https://www.google.com/",
            "cancel_url": "https://www.google.com/"
        }
    }
  end

  def user_credentials
    {
        username: "ASs8Osqge6KT3OdLtkNhD20VP8lsrqRUlRjLo-e5s75SHz-2ffMMzCos_odQGjGYpPcGlxJVQ5fXMz9q",
        password: "EKj_bMZn0CkOhOvFwJMX2WwhtCq2A0OtlOd5T-zUhKIf9WQxvgPasNX0Kr1U4TjFj8ZN6XCMF5NM30Z_"
    }
  end

  def options
    { headers: @headers }.merge(@body)
  end

  def billing_agreement_options
    {
        "description": "Billing Agreement",
        "shipping_address":
            {
                "line1": "1350 North First Street",
                "city": "San Jose",
                "state": "CA",
                "postal_code": "95112",
                "country_code": "US",
                "recipient_name": "John Doe"
            },
        "payer":
            {
                "payment_method": "PAYPAL"
            },
        "plan":
            {
                "type": "MERCHANT_INITIATED_BILLING",
                "merchant_preferences":
                    {
                        "return_url": "https://google.com",
                        "cancel_url": "https://google.com",
                        "accepted_pymt_type": "INSTANT",
                        "skip_shipping_address": false,
                        "immutable_shipping_address": true
                    }
            },
        headers: @headers
    }
  end

  def billing_options(billing_token)
    {
        "payment_source": {
            "token": {
                "id": billing_token,
                "type": "BILLING_AGREEMENT"
            }
        },
        "headers": @headers
    }
  end

  # Assertions private methods

  def success_create_order_assertions(order_type)
    assert create = @gateway.create_order(order_type, options)
    assert_instance_of Response, create
    assert_success create
    assert_equal order_type, create.params["intent"]
    assert_equal "CREATED", create.params["status"]
    assert_equal "Transaction Successfully Completed", create.message
    create
  end

  def success_update_assertions(order_id)
    assert update = @gateway.update_order(order_id, options.merge(body: {}))
    assert_instance_of Response, update
    assert_success update
    assert_empty update.params
    assert_equal "Transaction Successfully Completed", update.message
  end

  def success_capture_assertions(order_id)
    assert capture = @gateway.capture(order_id, @card_order_options)
    assert_instance_of Response, capture
    assert_success capture
    assert_equal "COMPLETED", capture.params["status"]
    assert_equal "Transaction Successfully Completed", capture.message
    capture
  end

  def success_authorize_assertions(order_id)
    assert authorize = @gateway.authorize(order_id, @card_order_options)
    assert_instance_of Response, authorize
    assert_success authorize
    assert_equal "COMPLETED", authorize.params["status"]
    assert_equal "Transaction Successfully Completed", authorize.message
    authorize
  end

  def success_capture_authorized_assertions(authorization_id)
    assert capture = @gateway.do_capture(authorization_id, options)
    assert_instance_of Response, capture
    assert_success capture
    assert_equal "COMPLETED", capture.params["status"]
    assert_equal "Transaction Successfully Completed", capture.message
  end

  def success_refund_assertions(capture_id)
    assert refund = @gateway.refund(capture_id, options)
    assert_instance_of Response, refund
    assert_success refund
    assert_equal "COMPLETED", refund.params["status"]
    assert_equal "Transaction Successfully Completed", refund.message
    refund
  end

  def success_void_assertions(authorization_id)
    assert void = @gateway.void(authorization_id, options)
    assert_instance_of Response, void
    assert_success void
    assert_empty void.params
    assert_equal "Transaction Successfully Completed", void.message
    void
  end

  def success_create_billing_agreement_assertions
    assert create = @gateway.create_billing_agreement_token(billing_agreement_options)
    assert_instance_of Response, create
    assert_success create
    assert !create.params["links"].nil?
    assert !create.params["token_id"].nil?
  end

  def success_approve_billing_agreement_assertions
    assert approve = @gateway.create_billing_agreement_token(billing_agreement_options)
    assert_instance_of Response, approve
    assert_success approve
    assert !approve.params["id"].nil?
    assert_equal "ACTIVE", approve.params["state"]
    approve
  end

  def success_capture_order_with_billing_assertions(order_id, billing_id)
    assert capture = @gateway.capture(order_id, billing_options(billing_id))
    assert_instance_of Response, capture
    assert_success capture
    assert_equal "COMPLETED", capture.params["status"]
    assert_equal "Transaction Successfully Completed", capture.message
  end

  def success_authorize_order_with_billing_assertions(order_id, billing_id)
    assert authorize = @gateway.authorize(order_id, billing_options(billing_id))
    assert_instance_of Response, authorize
    assert_success authorize
    assert_equal "COMPLETED", authorize.params["status"]
    assert_equal "Transaction Successfully Completed", authorize.message
  end

  def failed_create_order_invalid_schema_assertions
    assert create = @gateway.create_order("CAPTURE", options)
    assert_instance_of Response, create
    assert_failure create
    assert_equal "Request is not well-formed, syntactically incorrect, or violates schema.", create.message
    assert_equal "INVALID_REQUEST", create.params["name"]
  end

  def failed_create_order_invalid_business_validation_assertions
    assert create = @gateway.create_order("CAPTURE", options)
    assert_instance_of Response, create
    assert_failure create
    assert_equal "The requested action could not be performed, semantically incorrect, or failed business validation.", create.message
    assert_equal "UNPROCESSABLE_ENTITY", create.params["name"]
  end

  def failed_capture_order_invalid_schema_assertions(order_id)
    assert capture = @gateway.capture(order_id, @card_order_options)
    assert_instance_of Response, capture
    assert_failure capture
    assert_equal "Request is not well-formed, syntactically incorrect, or violates schema.", capture.message
    assert_equal "INVALID_REQUEST", capture.params["name"]
  end

  def failed_capture_order_invalid_business_validation_assertions(order_id)
    assert capture = @gateway.capture(order_id, @card_order_options)
    assert_instance_of Response, capture
    assert_failure capture
    assert_equal "The requested action could not be performed, semantically incorrect, or failed business validation.", capture.message
    assert_equal "UNPROCESSABLE_ENTITY", capture.params["name"]
  end

  def failed_authorize_order_invalid_business_validation_assertions(order_id)
    assert authorize = @gateway.authorize(order_id, @card_order_options)
    assert_instance_of Response, authorize
    assert_failure authorize
    assert_equal "The requested action could not be performed, semantically incorrect, or failed business validation.", authorize.message
    assert_equal "UNPROCESSABLE_ENTITY", authorize.params["name"]
  end

  def failed_authorize_order_invalid_schema_assertions(order_id)
    assert authorize = @gateway.authorize(order_id, @card_order_options)
    assert_instance_of Response, authorize
    assert_failure authorize
    assert_equal "Request is not well-formed, syntactically incorrect, or violates schema.", authorize.message
    assert_equal "INVALID_REQUEST", authorize.params["name"]
  end

  def failed_void_invalid_resource_assertions
    assert void = @gateway.void("INVALID_ID", options)
    assert_instance_of Response, void
    assert_failure void
    assert_equal "The specified resource does not exist.", void.message
    assert_equal "RESOURCE_NOT_FOUND", void.params["name"]
  end

  def failed_void_invalid_business_validation_assertions(authorization_id)
    assert void = @gateway.void(authorization_id, options)
    assert_instance_of Response, void
    assert_failure void
    assert_equal "The requested action could not be performed, semantically incorrect, or failed business validation.", void.message
    assert_equal "UNPROCESSABLE_ENTITY", void.params["name"]
  end

  def failed_refund_invalid_schema_assertions(capture_id)
    assert refund = @gateway.refund(capture_id, options)
    assert_instance_of Response, refund
    assert_failure refund
    assert_equal "Request is not well-formed, syntactically incorrect, or violates schema", refund.message
    assert_equal "INVALID_REQUEST", refund.params["name"]
  end

  def failed_refund_invalid_business_validation_assertions(capture_id)
    assert refund = @gateway.refund(capture_id, options)
    assert_instance_of Response, refund
    assert_failure refund
    assert_equal "The requested action could not be performed, semantically incorrect, or failed business validation.", refund.message
    assert_equal "UNPROCESSABLE_ENTITY", refund.params["name"]
  end

  def failed_update_assertions(order_id)
    assert update = @gateway.update_order(order_id, options.merge(body: {}))
    assert_instance_of Response, update
    assert_failure update
    assert_equal "The requested action could not be performed, semantically incorrect, or failed business validation.", update.message
    assert_equal "UNPROCESSABLE_ENTITY", update.params["name"]
  end

end
