# == Schema Information
#
# Table name: installation_configs
#
#  id               :bigint           not null, primary key
#  locked           :boolean          default(TRUE), not null
#  name             :string           not null
#  serialized_value :jsonb            not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_installation_configs_on_name                 (name) UNIQUE
#  index_installation_configs_on_name_and_created_at  (name,created_at) UNIQUE
#
class InstallationConfig < ApplicationRecord
  # https://stackoverflow.com/questions/72970170/upgrading-to-rails-6-1-6-1-causes-psychdisallowedclass-tried-to-load-unspecif
  # https://discuss.rubyonrails.org/t/cve-2022-32224-possible-rce-escalation-bug-with-serialized-columns-in-active-record/81017
  # FIX ME : fixes breakage of installation config. we need to migrate.
  # Fix configuration in application.rb
  class SerializedValueCoder
    PERMITTED_CLASSES = [ActiveSupport::HashWithIndifferentAccess].freeze

    def self.dump(value)
      return if value.nil?
      return value if value.is_a?(String)

      YAML.dump(value)
    end

    def self.load(value)
      return {}.with_indifferent_access if value.blank?
      return value.with_indifferent_access if value.is_a?(Hash)
      return {}.with_indifferent_access unless value.is_a?(String)

      parsed = YAML.safe_load(value, permitted_classes: PERMITTED_CLASSES, aliases: true)
      parsed.is_a?(Hash) ? parsed.with_indifferent_access : {}.with_indifferent_access
    rescue Psych::Exception, TypeError
      {}.with_indifferent_access
    end
  end

  serialize :serialized_value, coder: SerializedValueCoder, type: ActiveSupport::HashWithIndifferentAccess

  before_validation :set_lock
  validates :name, presence: true
  validate :saml_sso_users_check, if: -> { name == 'ENABLE_SAML_SSO_LOGIN' }

  # TODO: Get rid of default scope
  # https://stackoverflow.com/a/1834250/939299
  default_scope { order(created_at: :desc) }
  scope :editable, -> { where(locked: false) }

  after_commit :clear_cache

  def value
    # This is an extra hack again cause of the YAML serialization, in case of new object initialization in super admin
    # It was throwing error as the default value of column '{}' was failing in deserialization.
    raw_default = @attributes['serialized_value']&.value_before_type_cast
    return {}.with_indifferent_access if new_record? && (raw_default == '{}' || raw_default == {})

    serialized_value[:value]
  end

  def value=(value_to_assigned)
    self.serialized_value = {
      value: value_to_assigned
    }.with_indifferent_access
  end

  private

  def set_lock
    self.locked = true if locked.nil?
  end

  def clear_cache
    GlobalConfig.clear_cache
  end

  def saml_sso_users_check
    return unless value == false || value == 'false'
    return unless User.exists?(provider: 'saml')

    errors.add(:base, 'Cannot disable SAML SSO login while users are using SAML authentication')
  end
end
