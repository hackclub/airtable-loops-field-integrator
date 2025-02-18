class Payload < ApplicationRecord
  belongs_to :webhook

  validates :base_id, presence: true
  validates :body, presence: true
end
