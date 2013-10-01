# coding: utf-8 
require 'awesome_print'
require 'bunny'
require 'celluloid/autostart'
require "#{File.expand_path File.dirname __FILE__}/../config/simulation_data"
# PowerCompany
# 
# @author yshtak
# @description
#  電力事業所エージェント
#  ・価格決定 
#  ・オークション?
# 平均的な電力価格について
#  1kWh : 21yen
#  1kW15m : 21 / 4 = 5.25yen
#  1Wは 0.021yen
#
# 2013-08-17
#
class PowerCompany
  include Celluloid
  include Celluloid::Logger
  include SimulationData

  # constructor
  MIN_PRICE = 20 # kWhの価格
  MAX_PRICE = 35
  FIXED_MODEL = 0 # 固定買取価格
  DYNAMIC_MODEL = 1 # 変動買取価格
  attr_accessor :id, :trains
  def initialize cfg={}
    config = {
      lpg: 18000.0 * 3.0,
      timestep: 15,
      model_type: DYNAMIC_MODEL,
      id: 'pc_1',
      home_size: 1,
      belonging_homes: []
    }.merge(cfg)
    @id = config[:id]
    @tpp = 0.0 # Total Power Purchase
    @yield = 0.0 # 利益
    @tpg = 0.0 # Total Power Generation トータルの発電量/日
    @lpg = config[:lpg] # Limit Power Generation 発電制限量/日
    @timestep = config[:timestep]
    @onestep_tpp = 0.0 # onestep_lpg
    @onestep_tpg = 0.0 # onestep_lpg
    @onestep_lpg = @lpg/(24*60 / @timestep) # onestep_lpg
    @sell_price = price_curve # 電力価格初期化
    @purchase_price = purchase_curve # 買取価格初期化
    @model_type = config[:model_type] 
    @train_data = {}
    @belonging_homes = config[:belonging_homes] # 所属する家庭IDの配列
    @action_list = []
    @mails = []
    @output_data = []
    @trains = {
      SUNNY => [],
      RAINY => [],
      CLOUDY => []
    }
    @home_size = config[:home_size]
    @weather = SUNNY
    @clock = {day: 0, step: 0}
    ### Bunny Setting
    @bunny = Bunny.new
    @bunny.start
    @ch = @bunny.create_channel
    @reply_qs = Hash[@belonging_homes.map{|hid| [hid , @ch.queue("#{hid}",:auto_delete => true)]}]
    @my_q = @ch.queue("#{@id}", :auto_delete => true)
    ready_box
  end

  ## 一日の行動(1日まとめての行動)
  # mailの中身
  # buy:[FLOAT]
  # sell:[FLOAT]
  #
  def onestep_action time=0
   buy = 0.0
   askbuys = [] # 希望購入量配列
   sell = 0.0
   asksells = [] # 希望販売量配列
   pp = @purchase_price # 買取価格
   sp = @sell_price # 販売価格
   mt = @max_trade # 最大取引量
   onedata = {buy: 0.0, sell: 0.0, purchase_price: pp , sell_price: sp}
   ## メッセージの解凍
   @mails.each do |msg|
    ds = msg.split(",")
    reply_to = ds[0].gsub("id:","") # 先頭は必ずエージェントIDが送られてくる
    compose = "id:#{@id}," # 送るメッセージの初期化
    ds.each{|pay|
     case pay
     when /^buy:.*?/ ## ホームエージェントが買う 
      value = pay.gsub(/^buy:/,"").to_f
      @onestep_tpg = value # onestep用のpower generation
      sell_power value
      onedata[:buy] += value
      compose += "sell:#{value}," # 実際の購入量を通知
     when /^sell:.*?/ ## ホームエージェントが売る
      value = pay.gsub(/^sell:/,"").to_f
      @onestep_tpp = value # onestep用のpurchase_power
      purchase_power value
      onedata[:sell] += value
      compose += "buy:#{value}," # 実際の販売量を通知
     end
    }
    #Celluloid::Actor[reply_to].recieve_msg compose.chop # 家庭エージェントはメッセージを受け取る
    send_msg compose.chop, reply_to
   end

   onedata[:purchase_price] = @purchase_price # 更新
   onedata[:sell_price] = @sell_price # 更新
   #print "sell_power:",(onedata[:sell]*1000).round/1000.0,"\t\tbuy_power:",(onedata[:buy]*1000).round/1000.0,"\t\tpurchase_price:",
   #  (onedata[:purchase_price]*1000).round/1000.0,"\t\tsell_price:",(onedata[:sell_price]*1000).round/1000.0,"\n"
   @mails = [] # mailを空にする
   @output_data << onedata
   @trains[@weather] << onedata
  end

  ##
  # 
  # 
  def init_date
    self.csv_out # 10始まりに
    @tpg = 0.0
    @tpp = 0.0
    @sell_price = price_curve
    @purchase_price = purchase_curve
    refresh_trains
  end

  #
  # 販売価格決定
  def decide_sell_price 
   @sell_price = price_curve # 価格更新
  end
 
  #
  # 買取価格決定 
  # デフォルトは固定価格
  def decide_purchase_price
   @purchase_price = purchase_curve
  end

  #
  # 電力の買取
  def purchase_power value
   @tpp += value
   @yield -= value * @purchase_price
   ### 価格変動の影響
   decide_purchase_price # 価格更新
  end

  #
  # 電力の販売
  def sell_power value
   @tpg += value # 1日のトータル発電量更新
   @yield += value * @sell_price # 利益の追加
   decide_sell_price # 価格更新
  end

  # show power company status
  def dump
    info "販売価格:#{@sell_price},買取価格:#{@purchase_price},利益:#{@yield}\n"
    #ap "販売価格：#{@sell_price}\n買取価格：#{@purchase_price}\n利益：#{@yield}\n"
  end

  ######################## RabbitMQ #################################
  ###
  # ホームエージェントから受け取るメッセージボックス
  def recieve_msg msg
    @mails << msg
    if @mails.size == @home_size
      self.onestep_action @clock[:step] # step
      @clock[:step] += 1
      if @clock[:step] % (1440/TIMESTEP) == 0
        @clock[:day] += 1
        @clock[:step] = 0
      end
    end
  end

  def send_msg msg, reply_to
    @reply_qs[reply_to].publish msg
  end

  def ready_box
    @my_q.subscribe(:exclusive => true, :ack => true) do |delivery_info, properties, payload|
     self.recieve_msg "#{payload}"
     #puts "Received #{payload}, message properties are #{properties.inspect}"
    end
  end

  ####################################################################

  ###
  # save
  def csv_out
    cnt = @clock[:day]
    path = File.expand_path(File.dirname __FILE__) + "/../result/#{@id}_#{cnt}.csv"
    if cnt % 10 == 0 && cnt > 0
      file = open(path,'w')
      file.write "sell,buy,pruchase_price,sell_price\n"
      ap @output_data
      @output_data.each do |onedata|
        file.write "#{onedata[:sell]},#{onedata[:buy]},#{onedata[:purchase_price]},#{onedata[:sell_price]}\n"
      end
      @output_data = []
    end
  end

  ## 天気の設定
  def switch_weather sum_solar
   if SUNNY_BORDER < sum_solar
     @weather = SUNNY
   elsif CLOUDY_BORDER < sum_solar
     @weather = CLOUDY
   else
     @weather = RAINY
   end
  end

  #########################
  # 均衡店の決定
  def decide_equilibrium_point 
  end

  ## 
  # 価格と販売量（家庭が買う量）を決定
  # @askvalue: 家庭の希望購入量
  # @askprice: 家庭の希望販売量
  def decide_price_and_value askvalue, askprice
    
  end

  private
  ## 価格曲線の関数
  def price_curve
    alpha = 0.2
    value = 0.0
    if @onestep_lpg > @onestep_tpg
      value =  (MIN_PRICE)*(1.0 + alpha*(@onestep_tpg / (@onestep_lpg - @onestep_tpg))) ### kWh -> W15m
    else
      value =  (MIN_PRICE)*(1.0 + alpha*(@onestep_tpg / (@onestep_tpg - @onestep_lpg))) ### kWh -> W15m
    end
    #(MIN_PRICE / (1000 * 60/@timestep)) * (1 + alpha*(@tpg / (@lpg - @tpg))) ### kWh -> W15m
    #ap value / (1000*60/@timestep).to_f
    return value < MAX_PRICE ? value : MAX_PRICE  ### kWh -> W15m 
    #return value / (1000*60/@timestep).to_f ### kWh -> W15m 
  end

  ## 販売曲線（固定価格も可能）の関数
  def purchase_curve
    case @model_type
    when FIXED_MODEL
      return 38.0 / (1000*60/@timestep) # 2013年版(kWh -> W15m)
    when DYNAMIC_MODEL
      #x = ((@onestep_tpp + 0.1)/(@onestep_tpg+0.1))*100
      alpha = 0.2
      price =  MIN_PRICE * (1.0 - alpha *((@onestep_tpp / @onestep_lpg)))
      #return price / (1000*60/@timestep)
      return price
    end
    return 38.0 / (1000 * 60 / @timestep)
  end

  ### 
  # アクターを追加
  def add_actor actor
    Celluloid::Actor[actor.id] = actor
  end

  def refresh_trains
    @trains[@weather] = []
  end
end
