require 'smail/version'

module Smail
  @@options = {}
  @@override_options = {}
  @@subject_prefix = false
  @@append_inputs = false

# Default options can be set so that they don't have to be repeated.
#
#   Smail.options = { :from => 'noreply@example.com', :via => :smtp, :via_options => { :host => 'smtp.yourserver.com' } }
#   Smail.mail(:to => 'foo@bar') # Sends mail to foo@bar from noreply@example.com using smtp
#   Smail.mail(:from => 'Smail@example.com', :to => 'foo@bar') # Sends mail to foo@bar from Smail@example.com using smtp
  def self.options=(value)
    @@options = value
  end

  def self.options()
    @@options
  end

  def self.override_options=(value)
    @@override_options = value
  end

  def self.override_options
    @@override_options
  end

  def self.subject_prefix(value)
    @@subject_prefix = value
  end

  def self.append_inputs
    @@append_inputs = true
  end

# Send an email
#   Smail.mail(:to => 'you@example.com', :from => 'me@example.com', :subject => 'hi', :body => 'Hello there.')
#   Smail.mail(:to => 'you@example.com', :html_body => '<h1>Hello there!</h1>', :body => "In case you can't read html, Hello there.")
#   Smail.mail(:to => 'you@example.com', :cc => 'him@example.com', :from => 'me@example.com', :subject => 'hi', :body => 'Howsit!')
  def self.mail(options)
    if @@append_inputs
      options[:body] = "#{options[:body]}/n #{options.to_s}"
    end

    options = @@options.merge options
    options = options.merge @@override_options

    if @@subject_prefix
      options[:subject] = "#{@@subject_prefix}#{options[:subject]}"
    end

    fail ArgumentError, ':to is required' unless options[:to]

    options[:via] = default_delivery_method unless options.key?(:via)

    if options.key?(:via) && options[:via] == :sendmail
      options[:via_options] ||= {}
      options[:via_options][:location] ||= sendmail_binary
    end

    deliver build_mail(options)
  end

  def self.permissable_options
    standard_options + non_standard_options
  end

  private

  def self.deliver(mail)
    mail.deliver!
  end

  def self.default_delivery_method
    File.executable?(sendmail_binary) ? :sendmail : :smtp
  end

  def self.standard_options
    [
      :to,
      :cc,
      :bcc,
      :from,
      :subject,
      :content_type,
      :message_id,
      :sender,
      :reply_to,
      :smtp_envelope_to
    ]
  end

  def self.non_standard_options
    [
      :attachments,
      :body,
      :charset,
      :enable_starttls_auto,
      :headers,
      :html_body,
      :text_part_charset,
      :via,
      :via_options,
      :body_part_header,
      :html_body_part_header
    ]
  end

  def self.build_mail(options)
    mail = Mail.new do |m|
      options[:date] ||= Time.now
      options[:from] ||= 'Smail@unknown'
      options[:via_options] ||= {}

      options.each do |k, v|
        next if Smail.non_standard_options.include?(k)
        m.send(k, v)
      end

      if options[:attachments] && options[:html_body] && options[:body]
        part(:content_type => 'multipart/alternative') do |p|
          p.html_part = Smail.build_html_part(options)
          p.text_part = Smail.build_text_part(options)
        end

      elsif options[:html_body] || options[:attachments]
        if options[:html_body]
          m.html_part = Smail.build_html_part(options)
        end

        if options[:body]
          m.text_part = Smail.build_text_part(options)
        end

      elsif options[:body]
        body options[:body]
      end

      delivery_method options[:via], options[:via_options]
    end

    (options[:headers] ||= {}).each do |key, value|
      mail[key] = value
    end

    add_attachments(mail, options[:attachments]) if options[:attachments]

    mail.charset = options[:charset] if options[:charset] # charset must be set after setting content_type

    if mail.multipart? && options[:text_part_charset]
      mail.text_part.charset = options[:text_part_charset]
    end
    set_content_type(mail, options[:content_type])
    mail
  end

  def self.build_html_part(options)
    Mail::Part.new(:content_type => 'text/html;charset=UTF-8') do
      content_transfer_encoding 'quoted-printable'
      body Mail::Encodings::QuotedPrintable.encode(options[:html_body])
      if options[:html_body_part_header] && options[:html_body_part_header].is_a?(Hash)
        options[:html_body_part_header].each do |k,v|
          header[k] = v
        end
      end
    end
  end

  def self.build_text_part(options)
    Mail::Part.new(:content_type => 'text/plain') do
      content_type options[:charset] if options[:charset]
      body options[:body]
      if options[:body_part_header] && options[:body_part_header].is_a?(Hash)
        options[:body_part_header].each do |k,v|
          header[k] = v
        end
      end
    end
  end

  def self.set_content_type(mail, user_content_type)
    params = mail.content_type_parameters || {}
    content_type =  case
    when user_content_type
       user_content_type
    when mail.has_attachments?
      if mail.attachments.detect { |a| a.inline? }
        ["multipart", "related", params]
      else
        ["multipart", "mixed", params]
      end
    when mail.multipart?
      ["multipart", "alternative", params]
    else
      false
    end
    mail.content_type = content_type if content_type
  end

  def self.add_attachments(mail, attachments)
    attachments.each do |name, body|
      name = name.gsub /\s+/, ' '

      # mime-types wants to send these as "quoted-printable"
      if name =~ /\.xlsx$/
        mail.attachments[name] = {
          :content => Base64.encode64(body),
          :transfer_encoding => :base64
        }
      else
        mail.attachments[name] = body
      end
      mail.attachments[name].add_content_id("<#{name}@#{Socket.gethostname}>")
    end
  end

  def self.sendmail_binary
    sendmail = `which sendmail`.chomp
    sendmail.empty? ? '/usr/sbin/sendmail' : sendmail
  end
end
