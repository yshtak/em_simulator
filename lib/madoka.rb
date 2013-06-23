require 'bunny'
require 'awesome_print'
require 'uuidtools'

# RabbitMQサーバーとの接続クラス
# Exchange: Fanout
class Madoka
 attr_reader :config, :id, :channel

 def initialize cfg={}
  @config = {
    rabbitmq: {host: 'localhost'},
    exchange: 'madoka',
    auto_delete: true
   }.merge(cfg)
  @id = @config[:id] || UUIDTools::UUID.random_create.to_s
  @bunny = Bunny.new @config[:rabbitmq]
  @queue_list = []
  begin
   @bunny.start # 起動
   @channel = @bunny.create_channel # channel 作成
   @exchange = @channel.fanout(@config[:exchange])
  rescue => e
   p e.backtrace
  end
 end

 # Exchangeを受け取る
 def get_exchange
  @exchange
 end

 def recieve_message msg
  puts msg
 end

 # キューの名前でチャネルとbindする
 # Madokaクラスからbindされたキューに対してはfanoutができるようになる
 # queue_name: キューの名前（routing_key）
 def bind_queue queue_name
  # Queueを用意する
  # Queueを管理するときの注意
  @queue_list << queue_name
  q = @channel.queue(queue_name, :auto_delete => true).bind(@exchange)
  q.subscribe do |delivery_info, metadata, payload|
    self.recieve_message "[consumers] #{q.name} received a message '#{payload}'"  
  end
 end

 # return fanout queues
 def fanout_targets
  @queue_list
 end

 # メッセージを送信する
 # 送り先のExchangeを指定する
 # msg: メッセージ
 # reply_to_ex: 送り先のexchangeを指定できる
 def send_message msg
  @exchange.publish(msg)
 end

 def send_message_with_ex msg , ex
  ex.publish(msg)
 end

 # Close
 def close
  @channel.close
 end

 # Exchangeの削除
 def delete_exchange
  @exchange.delete
 end

 # Exchangeを作る
 def create_exchange ex_name
  @exchange = @channel.fanout ex_name if @exchange.nil?
 end

end
