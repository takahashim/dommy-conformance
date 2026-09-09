# frozen_string_literal: true

module DommyConformance
  module Wpt
    # One subtest result. `status` follows testharness.js's Test.statuses.
    Result = Struct.new(:name, :status, :message) do
      STATUS_NAMES = %w[PASS FAIL TIMEOUT NOTRUN].freeze

      def pass? = status.zero?
      def status_name = STATUS_NAMES[status] || "UNKNOWN(#{status})"
      def to_s = "[#{status_name}] #{name}#{message ? " \u2014 #{message}" : ""}"
    end
  end
end
