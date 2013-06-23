require 'bunny'
require 'uuidtools'

# Topic Exchange Class "Homra"
class Homra
 attr_reader :config, :id, :channel

 def initialize cfg={}
  @config = {
    rabbitmq: {host: 'localhost'},
    exchange: 'magical.girl',
    auto_delete: true,
   }.merge(cfg)
  @id = @config[:id] || UUIDTools::UUID.random_create.to_s
  @bunny = Bunny.new @config[:rabbitmq]
  @queue_list = []
  begin
   @bunny.start # 起動
   @channel = @bunny.create_channel # channel 作成
   @exchange = @channel.topic(@config[:exchange], :auto_delete => @config[:auto_delete])
  rescue => e
   p e.backtrace
  end
 end

 # Exchangeを取得
 def get_exchange
  return @exchange
 end

 # Routing Keyを指定してメッセージを送る
 # msg: メッセージ
 # routing_key: ルート
 #  
 def send_message_to_route msg, routing_key
  @exchange.publish(msg, :routing_key => routing_key)
 end

 # 別のExchangeにメッセージを渡すとき
 # options: routing_key
 #          app_id
 #          priority
 #          type
 #          header(metadata)
 #          timestamp
 #          reply_to
 #          correlation_id
 #          message_id
 # msg: メッセージ
 # ex: 他のexchange
 def send_message_with_ex msg, ex, options={}
  if options.empty?
   ex.publish(msg)
  else
   ex.publish(msg,options)
  end
 end

 # メッセージの受信
 # メッセージを受け取った時の処理
 def recieve_message msg
  puts msg
 end

 # exchangeにqueueをbindする. bindするためのroutingも行う
 # queue_name: キューの名前(ルートの階層関係も考慮される)
 #  例えば、magical.girl といった名前を指定すると 'magical.girl.#' のルーティングが適用され
 #  メッセージを'magical.girl.homra'指定で送ると、'magical.girl'のキューに飛ばされるようになる
 def bind_queue queue_name
  q = @channel.queue(queue_name, :auto_delete => true).bind(@exchange, :routing_key => "#{queue_name}.#")
  q.subscribe do |delivery_info, metadata, payload|
   self.recieve_message payload
  end
 end

end
