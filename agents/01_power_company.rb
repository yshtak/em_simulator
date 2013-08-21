# coding: utf-8 
require 'awesome_print'
require 'celluloid/autostart'
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

  # constructor
  MIN_PRICE = 20 # kWhの価格
  MAX_PRICE = 30
  FIXED_MODEL = 0 # 固定買取価格
  DYNAMIC_MODEL = 1 # 変動買取価格
  attr_accessor :id
  def initialize cfg={}
    config = {
      lpg: 6000000.0,
      timestep: 15,
      model_type: FIXED_MODEL,
      id: 'pc1'
    }.merge(cfg)
    @id = config[:id]
    @yield = 0.0 # 利益
    @tpg = 0.0 # Total Power Generation トータルの発電量/日
    @lpg = config[:lpg] # Limit Power Generation 発電制限量/日
    @timestep = config[:timestep]
    @sell_price = price_curve # 電力価格初期化
    @purchase_price = purchase_curve # 買取価格初期化
    @model_type = config[:model_type] 
    @train_data = {}
    @action_list = []
    @mails = []
  end

  ## 一日の行動(1日まとめての行動)
  # mailの中身
  # buy:[FLOAT]
  # sell:[FLOAT]
  #
  def day_action
   @mails.each do |msg|
    ds = msg.split(",")
    ds.each{|pay|
     case pay
     when /^buy:.*?/ ## ホームエージェントが買う 
      value = pay.gsub(/^buy:/,"").to_f
      sell_power value 
     when /^sell:.*?/ ## ホームエージェントが売る
      value = pay.gsub(/^sell:/,"").to_f
      purchase_power value
     end
    }
   end 
  end

  ##
  # 
  # 
  def init_date
   @tpg = 0.0
   @sell_price = price_curve
   @purchase_price = purchase_curve
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
  # 電力の買取価格
  def purchase_power value
   @yield -= value * @purchase_price
   ### 価格変動の影響
   decide_purchase_price # 価格更新
  end

  #
  # 電力の販売価格
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

  ###
  # ホームエージェントから受け取るメッセージボックス
  def recieve_msg msg
   @mails << msg
  end

  private
  ## 価格曲線の関数
  def price_curve
    alpha = 0.2 # 定数
    (MIN_PRICE / (1000 * 60/@timestep)) * (1 + alpha*(@tpg / (@lpg - @tpg))) ### kWh -> W15m
  end

  ## 販売曲線（固定価格も可能）の関数
  def purchase_curve
    case @model_type
    when FIXED_MODEL
      return 38.0 / (1000*60/@timestep) # 2013年版(kWh -> W15m)
    when DYNAMIC_MODEL
      return 38.0 / (1000*60/@timestep)
    end
    return 38.0 / (1000 * 60 / @timestep)
  end

  ### 
  # アクターを追加
  def add_actor actor
    Celluloid::Actor[actor.id] = actor
  end

end

