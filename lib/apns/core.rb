module APNS
  require 'socket'
  require 'openssl'
  require 'json'

  @host = 'gateway.sandbox.push.apple.com'
  @port = 2195
  # openssl pkcs12 -in mycert.p12 -out client-cert.pem -nodes -clcerts
  @pem_path = nil # this should be the path of the pem file not the contents
  @pem_file = nil # this should be the name of the pem file not the contents
  @pass = nil
  @ca_path = nil #entrust 2048 pem file

  class << self
    attr_accessor :host, :pem_path, :pem_file, :port, :pass, :ca_path
  end

  def self.send_notification(device_token, message, custom_pem = nil)
    n = APNS::Notification.new(device_token, message)
    self.send_notifications([n], custom_pem)
  end

  def self.send_notifications(notifications, custom_pem = nil)
    sock, ssl = self.open_connection(custom_pem)

    packed_nofications = self.packed_nofications(notifications)

    notifications.each do |n|
      ssl.write(packed_nofications)
    end

    ssl.close
    sock.close
  end

  def self.packed_nofications(notifications)
    bytes = ''

    notifications.each do |notification|
      # Each notification frame consists of
      # 1. (e.g. protocol version) 2 (unsigned char [1 byte]) 
      # 2. size of the full frame (unsigend int [4 byte], big endian)
      pn = notification.packaged_notification
      bytes << ([2, pn.bytesize].pack('CN') + pn)
    end

    bytes
  end

  def self.feedback
    sock, ssl = self.feedback_connection

    apns_feedback = []

    while message = ssl.read(38)
      timestamp, token_size, token = message.unpack('N1n1H*')
      apns_feedback << [Time.at(timestamp), token]
    end

    ssl.close
    sock.close

    return apns_feedback
  end

  def self.pem
    "#{self.pem_path}#{self.pem_file}"
  end

  protected

  def self.open_connection(custom_pem = nil)
    custom_pem = self.pem unless custom_pem.present?

    raise "The path to your pem file is not set. (APNS.pem = /path/to/cert.pem)" unless custom_pem
    raise "The path to your pem file does not exist!" unless File.exist?(custom_pem)

    context      = OpenSSL::SSL::SSLContext.new
    context.cert = OpenSSL::X509::Certificate.new(File.read(custom_pem))
    context.key  = OpenSSL::PKey::RSA.new(File.read(custom_pem), self.pass)
    context.ca_path =  self.ca_path #entrust 2048 pem file

    sock         = TCPSocket.new(self.host, self.port)
    ssl          = OpenSSL::SSL::SSLSocket.new(sock,context)
    ssl.connect

    return sock, ssl
  end

  def self.feedback_connection(custom_pem = nil)
    custom_pem = self.pem unless custom_pem.present?

    raise "The path to your pem file is not set. (APNS.pem = /path/to/cert.pem)" unless custom_pem
    raise "The path to your pem file does not exist!" unless File.exist?(custom_pem)

    context      = OpenSSL::SSL::SSLContext.new
    context.cert = OpenSSL::X509::Certificate.new(File.read(custom_pem))
    context.key  = OpenSSL::PKey::RSA.new(File.read(custom_pem), self.pass)

    fhost = self.host.gsub('gateway','feedback')
    puts fhost

    sock         = TCPSocket.new(fhost, 2196)
    ssl          = OpenSSL::SSL::SSLSocket.new(sock,context)
    ssl.connect

    return sock, ssl
  end
end
