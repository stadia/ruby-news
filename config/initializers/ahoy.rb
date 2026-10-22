# frozen_string_literal: true

class Ahoy::Store < Ahoy::DatabaseStore
end

Ahoy.api = false
Ahoy.geocode = false
Ahoy.mask_ips = true
Ahoy.server_side_visits = :when_needed
