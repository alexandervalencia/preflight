class InlineComment < ApplicationRecord
  belongs_to :pull_request

  validates :path, presence: true
  validates :body, presence: true
  validates :side, inclusion: { in: %w[left right] }
  validates :line_number, numericality: { only_integer: true, greater_than: 0 }
end
