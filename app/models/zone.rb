# == Schema Information
#
# Table name: zones
#
#  id              :integer          not null, primary key
#  name            :string(255)
#  primary_ns      :string(255)
#  email_address   :string(255)
#  serial          :integer
#  refresh_time    :integer
#  retry_time      :integer
#  expiration_time :integer
#  max_cache       :integer
#  ttl             :integer
#  published_at    :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#

require 'open3'

class Zone < ApplicationRecord

  # These control the spacing allocated to each column which is exported into
  # zone files.
  ZF_NAME_SPACE = 25
  ZF_TTL_SPACE = 8
  ZF_CLASS_SPACE = 4
  ZF_TYPE_SPACE = 10

  has_many :records, :dependent => :destroy

  validates :name, :presence => true, :hostname => true
  validates :primary_ns, :presence => true, :hostname => true
  validates :email_address, :presence => true, :email_address => true
  validates :serial, :numericality => {:only_integer => true, :allow_blank => true}
  validates :refresh_time, :numericality => {:only_integer => true}
  validates :retry_time, :numericality => {:only_integer => true}
  validates :expiration_time, :numericality => {:only_integer => true}
  validates :max_cache, :numericality => {:only_integer => true}
  validates :ttl, :numericality => {:only_integer => true}

  scope :stale, -> { where("published_at IS NULL OR updated_at > published_at") }

  default_value :refresh_time, -> { 3600 }
  default_value :retry_time, -> { 120 }
  default_value :expiration_time, -> { 2419200 }
  default_value :max_cache, -> { 600 }
  default_value :ttl, -> { 3600 }

  def generate_zone_file_header
    String.new.tap do |s|
      s << "# Zone file exported from Bound at #{Time.now.utc.to_s}\n"
      s << "# Bound Zone ID: #{id}\n\n"
      s << "$TTL".ljust(ZF_NAME_SPACE, ' ') + " #{self.ttl}\n"
      s << "$ORIGIN".ljust(ZF_NAME_SPACE, ' ') + " #{self.name}\n\n"
      s << "@".ljust(ZF_NAME_SPACE, ' ') + " "
      s << "IN".ljust(ZF_CLASS_SPACE, ' ')
      s << "SOA".ljust(ZF_TYPE_SPACE, ' ') + " "
      s << format_hostname(self.primary_ns) + " "
      s << format_email(self.email_address) + " "
      s << "("
      s << (self.serial || (0)).to_s + " "
      s << self.refresh_time.to_s + " "
      s << self.retry_time.to_s + " "
      s << self.expiration_time.to_s + " "
      s << self.max_cache.to_s
      s << ")"
    end
  end

  def generate_zone_file
    String.new.tap do |s|
      s << generate_zone_file_header
      s << "\n\n"
      s << records.order(:name).map(&:bind_line).join("\n")
    end
  end

  def generate_zone_clause
    String.new.tap do |s|
      s << "zone \"#{name}\" {\n"
      s << "  type master;\n"
      s << "  file \"#{zone_file_path}\";\n"
      s << "};"
    end
  end

  def format_hostname(hostname)
    if hostname.ends_with?('.')
      hostname
    else
      "#{hostname}.#{name}"
    end
  end

  def format_email(email_address)
    email_address.to_s.gsub('@', '.') + "."
  end

  def mark_as_published
    update_column(:published_at, Time.now)
  end

  def zone_file_path
    @zone_file_path ||= File.join(Bound::Publisher.zone_directory, "#{name}.zone")
  end

end