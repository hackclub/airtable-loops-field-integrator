class LoopsFieldBaseline < ApplicationRecord
  validates :email_normalized, :field_name, presence: true
  validates :email_normalized, uniqueness: { scope: :field_name }

  scope :expired, -> { where("expires_at < ?", Time.current) }

  # Fields to skip when seeding from Loops response (system fields, not writable properties)
  SYSTEM_FIELDS = %w[id email userId createdAt updatedAt unsubscribedAt listMemberships].freeze

  # Find or create a baseline for a given email and field
  def self.find_or_create_baseline(email_normalized:, field_name:)
    find_or_initialize_by(
      email_normalized: email_normalized,
      field_name: field_name
    )
  end

  # Update baseline with new sent value
  def update_sent_value(value:, expires_in_days: 90)
    self.last_sent_value = value
    self.last_sent_at = Time.current
    self.expires_at = Time.current + expires_in_days.days
    save!
  end

  # Check if contact exists in Loops and load baselines if needed
  # Returns true if contact exists (or we already have baselines), false if new contact
  # Side effect: If contact exists but we don't have baselines, loads them automatically
  def self.check_contact_existence_and_load_baselines(email_normalized:)
    # First check if we already have baselines for this email
    if where(email_normalized: email_normalized).exists?
      return true
    end

    # No baselines - check Loops API to see if contact exists
    contacts = LoopsService.find_contact(email: email_normalized)

    # Empty array means contact doesn't exist in Loops
    if contacts.empty?
      return false
    end

    # Contact exists - take the first one (find_contact returns array)
    contact_hash = contacts.first

    # Seed baselines from the contact's current properties
    seed_from_loops_response!(email_normalized, contact_hash)

    true
  end

  # Seed all writable properties from Loops response into LoopsFieldBaseline
  # Skip system fields like id, email, userId, timestamps, etc.
  def self.seed_from_loops_response!(email_normalized, contact_hash)
    seeded_count = 0

    contact_hash.each do |field_name, field_value|
      # Skip system fields
      next if SYSTEM_FIELDS.include?(field_name)

      # Skip nil values (they'll be set when we actually send data)
      next if field_value.nil?

      # Create or update baseline for this field
      baseline = find_or_create_baseline(
        email_normalized: email_normalized,
        field_name: field_name
      )

      baseline.update_sent_value(
        value: field_value,
        expires_in_days: 90
      )

      seeded_count += 1
    end

    seeded_count
  end

  # Generate initial payload for new contacts (userGroup and source fields)
  def self.initial_payload_for_new_contact(sync_source)
    source_value = humanized_source(sync_source)
    now = Time.current

    {
      "userGroup" => {
        value: "Hack Clubber",
        strategy: :upsert,
        modified_at: now
      },
      "source" => {
        value: source_value,
        strategy: :upsert,
        modified_at: now
      }
    }
  end

  # Generate humanized source string like "Airtable - Midnight RSVPs"
  def self.humanized_source(sync_source)
    type = sync_source.source.humanize
    name = sync_source.display_name || sync_source.source_id

    "#{type} - #{name}"
  end
end


