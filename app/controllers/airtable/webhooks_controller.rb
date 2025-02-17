module Airtable
  class WebhooksController < ApplicationController
    def receive
      puts 'Received webhook'
    end
end 