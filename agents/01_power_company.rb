# coding: utf-8 
require 'awesome_print'
#require ''
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
  #
  # constructor
  MIN_PRICE = 20 # kWhの価格
  MAX_PRICE = 30
  FIXED_MODEL = 0 # 固定買取価格
  DYNAMIC_MODEL = 1 # 変動買取価格
  def initializer cfg={}
    config = {
      lpg: 6000000.0,
      timestep: 15,
      model_type: FIXED_MODEL
    }.merge(cfg)
    @sell_price = price_curve # 電力価格初期化
    @purchase_price = purchase_curve # 買取価格初期化
    @yield = 0.0 # 利益
    @tpg = 0.0 # Total Power Generation トータルの発電量/日
    @lpg = config[:lpg] # Limit Power Generation 発電制限量/日
    @timestep = 15
    @model_type = config[:model_type] 
    @train_data = {}
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
    ap "販売価格：#{@sell_price}\n買取価格：#{@purchase_price}\n利益：#{@yield}\n"
  end

  private
  ## 価格曲線の関数
  def price_curve
    alpha = 0.2 # 定数
    (MIN_PRICE / (1000 * 60/@timestep)) * (1 + alpha(@tpg / (@lpg - @tpg))) ### kWh -> W15m
  end

  ## 販売曲線（固定価格も可能）の関数
  def purchase_curve
    case @model_type
    when FIXED_MODEL
      return 38.0 / (1000*60/@timestep) # 2013年版(kWh -> W15m)
    when DYNAMIC_MODEL
      ##return
      return 38.0 / (1000*60/@timestep)
    end
  end

end

