module Airtable
  class WebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token

    def receive
      WebhookNotificationHandler.set(wait: 15.seconds).perform_later(params[:base][:id], params[:webhook][:id], params[:timestamp])
    end
  end
end 