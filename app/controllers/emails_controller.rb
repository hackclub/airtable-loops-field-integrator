class EmailsController < ApplicationController
  def index
    # Get distinct emails ordered by most recent occurred_at
    @emails = LoopsContactChangeAudit
      .select(:email_normalized, 'MAX(occurred_at) as last_occurred_at')
      .group(:email_normalized)
      .order('MAX(occurred_at) DESC')
      .pluck(:email_normalized)
  end

  def show
    require 'uri'
    # Rails automatically URL-decodes params, but + characters might have become spaces
    # Get the email from the request path directly to avoid Rails' automatic decoding
    path_segment = request.path.split('/').last
    @email = URI.decode_www_form_component(path_segment)
    
    audits = LoopsContactChangeAudit.for_email(@email).order(occurred_at: :desc)
    
    # Bucket audits by 5-minute intervals
    @bucketed_audits = audits.group_by do |audit|
      # Round down to nearest 5-minute interval
      timestamp = audit.occurred_at
      minutes = timestamp.min
      rounded_minutes = (minutes / 5) * 5
      bucket_time = timestamp.change(min: rounded_minutes, sec: 0, usec: 0)
      bucket_time
    end
  end
end

