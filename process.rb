require 'serialport'
require 'time'
require 'net/http'
require 'uri'
require 'cgi'

class GSM
  
  #SMSC = "+447785016005"  # SMSC for Vodafone UK - change for other networks

  def initialize(options = {})
    @port = SerialPort.new(options[:port] , options[:baud] || 9600, options[:bits] || 8, options[:stop] || 1, SerialPort::NONE)
    @debug = options[:debug]
    cmd("AT")
    # Set to text mode
    cmd("AT+CMGF=1")
    # Set SMSC number
    #cmd("AT+CSCA=\"#{SMSC}\"")    
  end
  
  def close
    @port.close
  end
  
  def cmd(cmd)
    @port.write(cmd + "\r")
    wait
  end
  
  def wait
    buffer = ''
    while IO.select([@port], [], [], 0.25)
      chr = @port.getc.chr;
      print chr if @debug == true
      buffer += chr
    end
    buffer
  end

  def send_sms(options)
    cmd("AT+CMGS=\"#{options[:number]}\"")
    cmd("#{options[:message][0..140]}#{26.chr}\r\r")
    sleep 3
    wait
    cmd("AT")
  end
 
  def messages
    sms = cmd("AT+CMGL=\"ALL\"")
    # Ugly, ugly, ugly!
    msgs = sms.scan(/\+CMGL\:\s*?(\d+)\,.*?\,\"(.+?)\"\,.*?\,\"(.+?)\".*?\n(.*)/)
    return nil unless msgs
    msgs.collect!{ |m| GSM::SMS.new(:connection => self, :id => m[0], :sender => m[1], :time => m[2], :message => m[3].chomp) } rescue nil
  end
  
  class SMS
    attr_accessor :id, :sender, :message, :connection
    attr_writer :time
    
    def initialize(params)
	    @id = params[:id]; @sender = params[:sender]; @time = params[:time]; @message = params[:message]; @connection = params[:connection]
    end
    
    def delete
      @connection.cmd("AT+CMGD=#{@id}")
    end
    
    def time
      # This MAY need to be changed for non-UK situations, I'm not sure
      # how standardized SMS timestamps are..
      Time.parse(@time.sub(/(\d+)\D+(\d+)\D+(\d+)/, '\2/\3/20\1'))
    end
  end

end



p = GSM.new(:port => "/dev/ttyUSB2", :debug => false)

#destination_number = "+44 someone else"
# Send a text message
#p.send_sms(:number => destination_number, :message => "Test at #{Time.now}")

loop do
# Read text messages from phone
  p.messages.each do |msg|
    puts "#{msg.id} - #{msg.time} - #{msg.sender} - #{msg.message}"
    destination = msg.sender.to_s
    destination = destination[-10,10]
    count_before = p.messages.count
    msg.delete
    count_after = p.messages.count
    puts "Count before #{count_before} and count after #{count_after}"
    if count_before-count_after == 1
      search_message = msg.message
      search_message[" "] = "+" if search_message.include? " "
      url_location = "http://localhost:3000/coupons/find?msisdn=#{destination}&search=#{search_message}"
      url = URI.parse(url_location)
      res = Net::HTTP.start(url.host, url.port) {|http|
        http.get(url.request_uri)
      }
      message = res.body
      message = message.to_s
      message = CGI::escape(message)
      url_location = "http://myjingles.co.in/smspush/sendsms.php?msisdn=#{destination}&message=#{message}"
      puts url_location
      url = URI.parse(url_location)
      res = Net::HTTP.start(url.host, url.port) {|http|
        http.get(url.request_uri)
      }
      puts res.body
    end
  end
  sleep 5
end
