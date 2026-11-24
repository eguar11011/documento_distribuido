import Config

# Use shoehorn to start the main application. See the shoehorn
# library documentation for more control in ordering how OTP
# applications are started and handling failures.

config :shoehorn, init: [:nerves_runtime, :nerves_pack]

# Enable the system startup guard to check that all OTP applications
# started. If they didn't and you're on a Nerves system that supports
# test runs of new firmware, the firmware will automatically roll
# back to the previous version. Delete this if implementing your own
# way of validating that firmware is good.
config :nerves_runtime, startup_guard_enabled: true

# Erlinit can be configured without a rootfs_overlay. See
# https://github.com/nerves-project/erlinit/ for more information on
# configuring erlinit.

# Advance the system clock on devices without a real-time clock.
config :nerves, :erlinit, update_clock: true

# Default to not starting so that the console logger isn't started. See
# runtime.exs for logger configuration.
config :logger, :default_handler, false

# Configure the device for SSH IEx prompt access and firmware updates
#
# * See https://nerves-ssh.hexdocs.pm/readme.html for general SSH configuration
# * See https://ssh-subsystem-fwup.hexdocs.pm/readme.html for firmware updates

keys =
  System.user_home!()
  |> Path.join(".ssh/id_{rsa,ecdsa,ed25519}.pub")
  |> Path.wildcard()

if keys == [],
  do:
    Mix.raise("""
    No SSH public keys found in ~/.ssh. An ssh authorized key is needed to
    log into the Nerves device and update firmware on it using ssh.
    See your project's config.exs for this error message.
    """)

config :nerves_ssh,
  authorized_keys: Enum.map(keys, &File.read!/1)

# Configure the network using vintage_net
#
# Update regulatory_domain to your 2-letter country code E.g., "US"
#
# See https://github.com/nerves-networking/vintage_net for more information
hotspot_ssid = System.get_env("HOTSPOT_SSID")
hotspot_psk = System.get_env("HOTSPOT_PSK")
second_ssid = System.get_env("HOTSPOT_SSID_2")
second_psk = System.get_env("HOTSPOT_PSK_2")

if hotspot_ssid in [nil, ""] or hotspot_psk == nil or
     byte_size(hotspot_psk) < 8 or byte_size(hotspot_psk) > 63 do
  Mix.raise(
    "Configura HOTSPOT_SSID y HOTSPOT_PSK (clave WPA2 de 8 a 63 bytes) antes de compilar el firmware"
  )
end

if second_ssid in [nil, ""] != second_psk in [nil, ""] or
     (second_psk not in [nil, ""] and (byte_size(second_psk) < 8 or byte_size(second_psk) > 63)) do
  Mix.raise(
    "Configura HOTSPOT_SSID_2 y HOTSPOT_PSK_2 juntos; la clave debe tener entre 8 y 63 bytes"
  )
end

networks = [%{key_mgmt: :wpa_psk, ssid: hotspot_ssid, psk: hotspot_psk, priority: 1}]

networks =
  if second_ssid in [nil, ""] do
    networks
  else
    networks ++ [%{key_mgmt: :wpa_psk, ssid: second_ssid, psk: second_psk, priority: 2}]
  end

config :vintage_net,
  regulatory_domain: "CO",
  config: [
    {"usb0", %{type: VintageNetDirect}},
    {"eth0",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :dhcp}
     }},
    {"wlan0",
     %{
       type: VintageNetWiFi,
       vintage_net_wifi: %{
         networks: networks
       },
       ipv4: %{method: :dhcp}
     }}
  ]

config :mdns_lite,
  # The `hosts` key specifies what hostnames mdns_lite advertises.  `:hostname`
  # advertises the device's hostname.local. For the official Nerves systems, this
  # is "nerves-<4 digit serial#>.local".  The `"nerves"` host causes mdns_lite
  # to advertise "nerves.local" for convenience. If more than one Nerves device
  # is on the network, it is recommended to delete "nerves" from the list
  # because otherwise any of the devices may respond to nerves.local leading to
  # unpredictable behavior.

  hosts: [:hostname],
  ttl: 120,

  # Advertise the following services over mDNS.
  services: [
    %{
      protocol: "ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "sftp-ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "epmd",
      transport: "tcp",
      port: 4369
    }
  ]

config :documento_distribuido,
  historial: "/data/cpd_doc/historial.log",
  epoca: "/data/cpd_doc/epoca"

# Import target specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# Uncomment to use target specific configurations

# import_config "#{Mix.target()}.exs"
