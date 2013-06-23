require 'bunny'
require 'celluloid'
require 'uuidtools'

# RabbitMQと接続するためのクラス(1:1)
# インスタンス化した際にqueueはexchangeにbindされないので
# bind_queueでbindする必要がある
class Moppy
 attr_reader :qname, :id, :queue, :route

 def initialize cfg={}
  @config = {
   rabbitmq: {host: 'localhost'},
   exchange: 'moppy',
   queue_delete: true
  }.merge(cfg)
  @id = @config[:id] || UUIDTools::UUID.random_create.to_s
  @bunny = Bunny.new @config[:rabbitmq]
  begin
   @bunny.start # 起動
   @channel = @bunny.create_channel # channel 作成
   @exchange = @channel.direct(@config[:exchange])
  rescue => e
   p e.backtrace
  end
 end

 # メッセージの送信:(Direct)
 # reply: 送り先の相手(@qname)
 # msg: 送るメッセージ
 def send_message msg, reply=nil
  if reply
   @exchange.publish(msg, routing_key: reply)
  else
   @exchange.publish(msg)
  end
 end
 
 # 全員(fanoutのexchangeにbindされた複数キュー)にメッセージを送る
 # msg: 送るメッセージ
 # ex: fanoutのexchangeを指定 
 def send_message_with_ex msg, ex
  ex.publish(msg)
 end

 # メッセージを受け取った際に実行する処理
 # msg: メッセージ
 def recieve_message msg
  puts "[#{@id}][Recive message: '#{msg}']"
 end

 # 現在のキューの状態を確認する 
 def check_own_queue
  puts @queue
 end


 ## RabbitMQとの接続を切断
 def stop_connection
  @bunny.stop
 end

 def bind_queue queue_name=nil
  ## channelのキューとの関連付けを定義する
  ## メッセージを受け取った時の動作を定義
  @route = @id if queue_name.nil?
  q = @channel.queue(@id , :auto_delete => true).bind(@exchange,:routing_key => @route)
  q.subscribe do |delivery_info, metadata, payload|
   # 受け取ったメッセージの処理
   self.recieve_message payload
  end
 end

 private 

end
