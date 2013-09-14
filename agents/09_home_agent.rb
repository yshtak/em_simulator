# coding: utf-8 
require 'celluloid/autostart'
require "#{File.expand_path File.dirname __FILE__}/../filter/06_particle_filter"
require "#{File.expand_path File.dirname __FILE__}/../config/simulation_data"
require "#{File.expand_path File.dirname __FILE__}/../lib/01_differential_evolutions"
#========================================================
#
# Home Agent v8.0
# 2013-07-27
#  - 新しいParticle Filterを導入
# 2013-07-30
#  - 夜間に電力をまとめて買う戦略の導入
# 2013-08-18
#  - ActorModelの導入 mailboxでメッセージを受け取るよう
#  に設定
# 2013-08-30
#  - 最適化問題の追加
#
#========================================================
class HomeAgent
 attr_accessor :strage, :target, :filter, :id
 SIM_INTERVAL = 24 * 4 # 15分刻み
 include SimulationData
 include Celluloid

 def initialize cfg={}
  config = {
   id: "nagoya01",
   filter: 'none', # 未来予測のためのフィルターのタイプ
   max_strage: 10000.0, # 蓄電容量(Wh)
   target: 500.0, # 目標蓄電量(Wh)
   buy_target_ratio: 0.35, # 30%
   sell_target_ratio: 0.75, # 40%
   solars: [], # 15分毎の1日の電力発電データ
   demands: [], # 15分毎の1日の需要データ
   address: "unknown",
   strategy: NORMAL_STRATEGY,
   limit_power: 2000.0,
   chunk_size: 5,
   midnight_ratio: 0.8, # 夜間に購入する目標充電率
   midnight_strategy: true, # 夜間戦略ありなし
   midnight_interval: 4,
   contractor: nil # 電力事業所エージェントのポインター
  }.merge(cfg)
  ## debug
  ap config
  # データの初期化
  @id = config[:id]
  @simdatas = []
  @strategy = config[:strategy]
  @my_contractor = config[:contractor] # ポインター受け渡し
  @chunk_size = config[:chunk_size] # 学習データサイズ
  @midnight_ratio = config[:midnight_ratio] #
  @midnight_interval = config[:midnight_interval] #
  @midnight_strategy = config[:midnight_strategy] #
  @max_strage = config[:max_strage] # 最大容量
  @battery = 2000.0 # 蓄電量の初期値
  @address = config[:address] # 地域や住所（ex, nagoya, okazaki）
  @weather = -1 # none 
  @oneday_buys = Array.new((1440/TIMESTEP), 0.0) # 一日の買った電力をタイプステップごとで記録し学習
  @oneday_sells = Array.new((1440/TIMESTEP), 0.0) # 一日の売った電力をタイムステップごとで記録し学習
  @oneday_battery = Array.new((1440/TIMESTEP), 0.0) 
  @filter = filter_init config[:filter]
  @target = config[:target] # 目標充電量
  @buy_target = @max_strage * config[:buy_target_ratio] # 買いの購入の意思決定閾値（蓄電量）
  @sell_target = @max_strage * config[:sell_target_ratio] # 買いの購入の意思決定閾値（蓄電量）
  @solars = config[:solars] # 太陽光発電量のデータ（シミュレーション用）
  @demands = config[:demands] # 需要（電力消費）データ（シミュレーション用）
  @clock = {:step => 0, :day => 0} # エージェント内時計
  # 学習データ
  @trains={
   demands:{
    SUNNY => [], RAINY => [], CLOUDY => []
   },
   solars:{
    SUNNY => [], RAINY => [], CLOUDY => []
   },
   buys:{
    SUNNY => [], RAINY => [], CLOUDY => []
   },
   sells:{
    SUNNY => [], RAINY => [], CLOUDY => []
   },
   p_sell_price:{
    SUNNY => [], RAINY => [], CLOUDY => []
   },
   p_purchase_price:{
    SUNNY => [], RAINY => [], CLOUDY => []
   },
   battery:{
     SUNNY => [], RAINY => [], CLOUDY => []
   },
  }
  @buy_times = (0...(1440/TIMESTEP)).map{|i| (25.0*Random.rand(10.0)+10) + Random.rand(100.0)} # 一日の間に時間別で購入する量の配列
  @sell_times = (0...(1440/TIMESTEP)).map{|i| (25.0*Random.rand(10.0)+10) + Random.rand(85.0)} # 一日の間に時間別に販売する量の配列
  #@buy_times = Array.new((1440/TIMESTEP),0.0) # 一日の間に時間別で購入する量の配列
  #@sell_times = Array.new((1440/TIMESTEP),0.0) # 一日の間に時間別に販売する量の配列
  @may_get_solar = 0.0 # 次の日に得られる発電量
  @yield = 0.0 # 家庭エージェントの利益
  b = (1440/TIMESTEP)
  #weight_func = -> (x) {(6.0/(2.0*(b**2)-3.0 * (b**1) + 1)) * (x-b)**2 } # 重み関数
  weight_func = -> (x) { - 2.25 / b * x + 2.25} # 重み関数
  @weights = [] # 重み関数の初期化（徐々に重みが減っていく.）
  (0..b-1).each do |index|
    @weights << weight_func.call(index) ## 重み関数
  end
 end

 # 需要量のセット
 def set_demands datas
  @demands.clear
  @demands = datas
 end

 # 太陽光発電量をセット
 def set_solars datas
  @solars=[]
  @solars = datas.map{|x| x*0.85 } # 発電効率85%
 end

 ### version 0.9 逐次的処理 ##########################################
 # 一日の行動
 def onestep_action time
   @clock[:step] = time
   @clock[:day] += 1 if (time+1) == (1440/TIMESTEP)
   self.action time
   #self.decide_sell_power #
   #self.decide_buy_power #
 end

 # 購入する電力量の決定 
 def action cnt
   simdata = {}
   simdata[:weather] = @weather
   simdata[:battery] = @battery
   case @strategy # default is normal strategy
   when NORMAL_STRATEGY
     simdata[:demand] = @demands[cnt] #
     simdata[:solar] = @solars[cnt] #
     buy_plus = 0.0 # 足りない分の電力を余分に購入する分
     sell_plus = 0.0 # 容量を超えてしまわないように売る量を微調整
     @battery = @battery - simdata[:demand] + simdata[:solar] # 購入量と販売量考慮せずの蓄電池の更新

     ## バッテリー
     if @battery < 0.0 # batteryが0.0以下になる場合は
       buy_plus = @battery.abs
       @battery = 0.0
     elsif @battery > @max_strage
       @battery = @max_strage
       sell_plus = @battery - @max_strage
     end
     # 購入量と販売量の変更
     simdata[:buy] = @buy_times[cnt] + buy_plus
     simdata[:sell] = @sell_times[cnt] + sell_plus
     if @battery > 0.0
       simdata[:sell] = @battery - simdata[:sell] < 0.0 ? @battery : simdata[:sell] # battery 0回避
       simdata[:buy] = @battery + simdata[:buy] > @max_strage ? @max_strage - @battery : simdata[:buy] # 蓄電池容量制約
       @battery = @battery + simdata[:buy] - simdata[:sell]
     elsif # @battery == 0.0 のとき
       @battery = @battery + simdata[:buy]
       simdata[:sell] = 0.0 # 必ず 0.0
     end
     simdata[:predict] = @solars[cnt]
     simdata[:battery] = @battery
     ##### 電力事業所にメッセージング
     send_message "id:#{@id},buy:#{simdata[:buy]},sell:#{simdata[:sell]}" 
   when SECOND_STRATEGY

   when THIRD_STRATEGY
   end
   @oneday_battery[@clock[:step]] = @battery # @clockを使うのはプログラムの統一性を図るため
   @simdatas << simdata
   return simdata
 end

 #### 一日始まるときに行動する内容 ####################################33
 def day_start_action
   time = Time.now
   ap "最適化開始 --"
   @buy_times, @sell_times = optimum_oneday
   ap "最適化終了 -- 経過時間 #{(Time.now - time)/60.0}mins"
 end

 ##
 # 一日の最適化問題を解くメソッド
 def optimum_oneday
   demands = self.smooth_demand_train_data
   solars = self.smooth_solar_train_data
   #buys = self.smooth_buy_train_data
   #sells = self.smooth_sell_train_data 
   #purchase_prices = self.smooth_p_purchase_price
   sell_prices = self.smooth_p_sell_price
   battery = self.smooth_battery_train_data
   # DifferentialEvolution用の初期パラメータ設定
   params = {
     step: TIMESTEP,
     #purchase_prices: purchase_prices,
     sell_prices: sell_prices,
     battery: battery,
     demands: demands,
     solars: solars,
     max_strage: @max_strage
   }
   df = DifferentialEvolution::instance params 
   # configuration
   search_space = Array.new((1440/TIMESTEP)*2,Array.new([0,500]))
   problem_size = search_space.size
   pop_size = 10 * problem_size
   max_gens = 200
   weightf = 0.8
   crossf = 0.9
   best = df.search(max_gens, search_space, pop_size, weightf, crossf)

   buys = best[:vector][0...(1440/TIMESTEP)]
   #sells = best[:vector][(1440/TIMESTEP)...2*(1440/TIMESTEP)]
   return buys  
 end

 #####################################################################
 #
 # 各時間での目標蓄電量の計算 ( b_ref )
 #  考え方
 #   
 #
 #####################################################################
 

 #####################################################################
 
 #####################################################################
 # 買う量を決定（価格と量を返り値とする）
 # 引数
 #  d0: 現在の需要量
 #  d1: 次のの需要量 
 #  s0: 現在の太陽光発電量
 #  s1: 予測の太陽光発電量
 # 戦略は需要量から発電量を引いた値の正負で変わることに注意
 # 内部プログラムのt0,t1は絶対値であり，各ケース内の場合分け
 # で用いられる.
 def buy_and_sell_power d0, d1, s0, s1,time
  max_buy = 500.0
  fix_buy_power = @buy_times[time] # 最初に決めておいた購入量
  fix_sell_power = @sell_times[time]
  t0 = (d0 - s0).abs
  t1 = (d1 - s1).abs
  buy_value = fix_buy_power # 買電量の初期化
  sell_value = fix_sell_power # 売電量の初期化
  ## 単純なピーク時間を判断する（14時まえはなるべく少なめに電力を購入する（天候によって偏りあり））
  beta = 1.0 # 天候による日中に差し掛かるまでの間の消費者行動係数 (( 最後に調整する
  if time < 14 * (60/TIMESTEP)
    case @weather
    when SUNNY
      beta = 0.2 # 比重あり
    when CLOUDY
      beta = 0.25 # 比重あり
    when RAINY
      beta = 1.0 # 比重なし
    end
  end
  #print "solar:#{s0}, demand:#{d0}\n"
  ################# １日始まるときに決定した購入量について
  if fix_buy_power == 0.0 # 買おうとしていない場合
    if @battery  - (d0 - s0) > @buy_target ## 買う行動の目標となるしきい値を超えるかどうか
      @battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0 
      @battery = @battery - d0 + s0
      return 0.0, 0.0 # 購入しない
    end
  end
  ################## 逐次的による戦略
  if (d0 - s0) > 0 && (d1 - s1) > 0 # Case 1 ------------------
   if @battery - (t0  + t1) < 0 # 予測と現在の需要和が現時点の蓄電量を超えるとき（空になる）
    buy_value = @battery + t1 > @max_strage ? @max_strage - @battery : t0 + t1
   elsif @battery - (t0 + t1) > 0 && @battery - (t0 + t1) < @buy_target # 未来予測後も目標値以下のとき
    value = @battery + t1 <= @max_strage ? t0 + t1 : @max_strage - @battery
    #p t1
    #p value
   elsif @battery - (t1 + t0) <= @max_strage # それ以外は買わない
    # 買わない
    #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0 
    sell_value = sell_power
   end
  elsif d0 - s0 > 0 && d1 - s1 <= 0 # Case 2 -------------------
   if @battery - (t0 - t1) > 0 && @battery - (t0 - t1) <= @buy_target
    buy_value = t0 - t1
    #p value
   elsif @battery - (t0 - t1) > @buy_target
    if @battery - t0 < 0
     buy_value =  t0 + @buy_target - @battery
     #p value
    elsif @battery - t0 > 0
     # 買わない
     #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
     sell_value = sell_power
    end
   end
   # Exception
   return 0.0, 0.0
  elsif d0 - s0 <= 0 && d1 - s1 > 0 # Case 3 -------------------
   if @battery + t0 - t1 >= @buy_target
    # 買わない
    #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
   elsif @battery + t0 - t1 < @buy_target
    if @battery + t0 > @max_strage
     # 買わない
     #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
     sell_value = sell_power
    elsif @battery + t0 <= @max_strage
     #value = @max_strage - (@battery + t1)
     buy_value = t1 - t0
     #p value
    end
   end
  elsif d0 - s0 <= 0 && d1 - s1 <= 0 # Case 4 -------------------
   if @battery + t0 + t1 < @buy_target
    buy_value = @buy_target - (@battery + (t0 + t1))
   else
    #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
    sell_value = sell_power
   end
  end
  buy_value = max_buy > buy_value ? buy_value : max_buy
  buy_value *= beta # 電力が得られ始める段階ではあまり買わない
  p sell_value
  @battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0 
  @battery = @battery - d0 + buy_value
  @battery = 0.0 if @battery < 0.0
  return buy_value, sell_value
 end

 # ２つ先がどうなるかも考慮に入れる
 # 買いが乱高下しないようにするための戦略
 # 現在時刻:time
 def buy_and_sell_power_2step d0, d1, s0, s1, time
  max_buy = 500.0
  fix_buy_power = @buy_times[time] # 最初に決めておいた購入量
  fix_sell_power = @sell_times[time] # 最初に決めておいた購入量
  t0 = (d0 - s0).abs
  t1 = (d1 - s1).abs
  # 二期先のデータを定義する
  d2 = @demands[time+2]
  s2 = @filter.ave_models[@weather][time+2]
  #s2 = @weather_models[@weather][time+2]
  t2 = (d2 - s2).abs # 需要の差分
  ## 単純なピーク時間を判断する（14時まえはなるべく少なめに電力を購入する（天候によって偏りあり））
  beta = 1.0 # 天候による日中に差し掛かるまでの間の消費者行動係数 (( 最後に調整する
  if time < 14 * (60/TIMESTEP)
    case @weather
    when SUNNY
      beta = 0.2 # 比重あり
    when CLOUDY
      beta = 0.25 # 比重あり
    when RAINY
      beta = 1.0 # 比重なし
    end
  end
 
  buy_value = fix_buy_power # 買電量の初期化
  sell_value = fix_sell_power # 売電量の初期化
  ################# １日始まるときに決定した購入量について
  if fix_buy_power == 0.0 # 買おうとしていない場合
    if @battery  - (d0 - s0) > @buy_target ## 買う行動の目標となるしきい値を超えるかどうか
      #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0 
      #@battery = @battery - d0 + s0
      return 0.0, 0.0 # 購入しない
    end
  end
  ################## 逐次的による戦略
  #print "solar:#{s0}, demand:#{d0}\n"
  if (d0 - s0) > 0 && (d1 - s1) > 0 # Case 1 ------------------
   if @battery - (t0  + t1) < 0 # 予測と現在の需要和が現時点の蓄電量を超えるとき（空になる）
    buy_value = @battery + t1 > @max_strage ? @max_strage - @battery : t0 + t1
    if d2 - s2 > 0 # ２つ先の需要と供給の差(需要が多いかどうか) 
     buy_value = (buy_value + t2)*0.7 / 2.0 
    else
     buy_value = buy_value - t2 < 0.0 ? 0.0 : buy_value - t2
    end
   elsif @battery - (t0 + t1) > 0 && @battery - (t0 + t1) < @buy_target # 未来予測後も目標値以下のとき
    buy_value = @battery + t1 <= @max_strage ? t0 + t1 : @max_strage - @battery
    if d2 - s2 > 0
     buy_value = (buy_value + t2)*0.7/2.0
    else
     buy_value = buy_value - t2 < 0.0 ? 0.0 : buy_value - t2
    end
    #p t1
    #p value
   elsif @battery - (t1 + t0) <= @max_strage # それ以外は買わない
    # 買わない
    #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
    if (d2 - s2) > 0
     buy_value = t2 if @battery - (t1 + t0) - t2 < @buy_target
    else
     sell_value = sell_power time
    end
   end
  elsif d0 - s0 > 0 && d1 - s1 <= 0 # Case 2 -------------------
   if @battery - (t0 - t1) > 0 && @battery - (t0 - t1) <= @buy_target
    buy_value = t0 - t1
    if d2 - s2 > 0
     buy_value = (buy_value + t2)*0.7/2.0 
    else
     buy_value = buy_value - t2 < 0.0 ? 0.0 : buy_value - t2
    end
    #p value
   elsif @battery - (t0 - t1) > @buy_target
    if @battery - t0 < 0
     buy_value =  t0 + @buy_target - @battery
     if d2 - s2 > 0
      buy_value = (buy_value + t2)*0.7/2.0
     else
      buy_value = buy_value - t2 < 0.0 ? 0.0 : buy_value - t2
     end
     #p value
    elsif @battery - t0 > 0
     # 買わない
     #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
     if d2 - s2 > 0
      buy_value = t2 if @battery - t0 - t2 < @buy_target
     else
      sell_value = sell_power time
     end
    end
   end
   # Exception
   return buy_value, sell_value
  elsif d0 - s0 <= 0 && d1 - s1 > 0 # Case 3 -------------------
   if @battery + t0 - t1 >= @buy_target
    # 買わない
    #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
    if d2 - s2 > 0
     buy_value = t2 if @battery + t0 -t1 - t2 < @buy_target
    else
     sell_value = sell_power time
    end
   elsif @battery + t0 - t1 < @buy_target
    if @battery + t0 > @max_strage
     # 買わない
     #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
     if d2 - s2 > 0
      buy_value = t2 if @battery + t0 - t2 < @buy_target
     else
      sell_value = sell_power time
     end
    elsif @battery + t0 <= @max_strage
     #value = @max_strage - (@battery + t1)
     buy_value = t1 - t0
     if d2 - s2 > 0
      buy_value = (buy_value + t2)*0.7/2.0 
     else
      buy_value = buy_value - t2 < 0.0 ? 0.0 : buy_value - t2
     end
     #p value
    end
   end
  elsif d0 - s0 <= 0 && d1 - s1 <= 0 # Case 4 -------------------
   if @battery + t0 + t1 < @buy_target
    buy_value = @buy_target - (@battery + (t0 + t1))
    if d2 - s2 > 0 ## 2013-07-31変更
     buy_value = (buy_value + t2)*0.7/2.0 
    else
     buy_value = buy_value - t2 < 0.0 ? 0.0 : buy_value - t2
    end
   else
    #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
    if d2 - s2 > 0
     buy_value = t2 if @battery + t0 + t1 - t2 < @buy_target
    else
     sell_value = sell_power time
    end
   end
  end
  buy_value = max_buy > buy_value ? buy_value : max_buy
  buy_value *= beta # 電力が得られ始める段階ではあまり買わない
  buy_value = 0.0 if buy_value < 0.0 # マイナス回避
  sell_value = 0.0 if sell_value < 0.0 || buy_value > 0.0 # マイナス回避
  #@battery = @battery + s0 - d0 + buy_value > @max_strage ? @max_strage : @battery + s0 - d0 + buy_value
  #@battery = 0.0 if @battery < 0.0
  #@battery = @battery - d0 + value
  return buy_value, sell_value 
 end

 ###
 # 最新版: 2013-08-29
 #
 def buy_and_sell crnt_demand, next_demand, crnt_solar, next_solar, time, type=0
   max_transition = 500.0
   #cnrt_consumption = crnt_demand - crnt_solar # 現在時刻の消費量
   #next_consumption = next_demand - next_solar # 真の消費量
   #askbuy = crnt_demand - cnrt_solar 
   next_battery = @battery - crnt_demand + crnt_solar # 次の蓄電池の容量
   #next_battery = 0.0 if next_battery < 0.0
   ## 単純なピーク時間を判断する（14時まえはなるべく少なめに電力を購入する（天候によって偏りあり））
   beta = 1.0 # 天候による日中に差し掛かるまでの間の消費者行動係数 (( 最後に調整する
   if time < 14 * (60/TIMESTEP)
     case @weather
     when SUNNY
       beta = 0.2 # 比重あり
     when CLOUDY
       beta = 0.25 # 比重あり
     when RAINY
       beta = 1.0 # 比重なし
     end
   end
   ####
   askbuy = @buy_times[time]
   asksell = 0.0
   case type
   when 0 ## normal
     ### 購入目標に達成しているかどうか ##################### normal #########################
     if next_battery < 0.0 ## 絶対に購入
       asksell = max_transition # MAX
     elsif next_battery < @buy_target # 購入目標値より下回れば買わなければならない
       if next_demand < next_solar ## 十分な発電量が得られるとき
         if crnt_demand < crnt_solar ## 電力が十分偉える
           diff = @buy_target - next_battery - (next_solar - next_demand) # 次の微量の発電量を
           askbuy = diff < 0.0 ? 0.0 : crnt_demand # 買わなくても次に貯まる 
         else ## 一期先の需要が多い
           diff = @buy_target - next_battery - next_solar + next_demand
           askbuy = diff < 0.0 ? crnt_demand + next_demand : crnt_demand # 少し多めに買う
         end
       else # 需要が多い
         if crnt_demand < crnt_solar # 発電量が多い
           diff = @buy_target - (next_battery - next_demand + next_solar)
           askbuy = diff < 0.0 ? 0.0 : diff
         else # 需要が多い
           diff = next_battery - next_demand + crnt_demand
           askbuy = crnt_demand + next_demand
         end
       end
     elsif @sell_target < next_battery ## 基本的に電力を売る
       if next_demand < next_solar ## 一つ先で十分な発電量が得られるとき
         if crnt_demand < crnt_solar ## 十分な充電量が得られるとき
           diff = @battery - crnt_demand # 消費したときにbatteryがなくなるかどうかの条件式
           asksell = diff < 0.0 ? crnt_solar - crnt_demand : crnt_solar # 0にならない限り殆ど売る
         else # 現在時刻では基本電力が減る
           ### next_batteryがbuy_targetより小さくなることはありえない
           asksell = @buy_target - next_battery # 理想的販売量
         end
       else # 一つ先で需要が多い
         if crnt_demand < crnt_solar
           diff = (crnt_solar - crnt_demand) - (next_demand - next_solar) # 次の時刻で消費するであろう電力と現在時刻で蓄える電力の差
           asksell = diff < 0.0 ? next_battery - @buy_target + diff : diff # diffが0.0以下なら限りなく少ない電力量だが売る
           asksell = 0.0 if asksell < 0.0 # 0.0以下になる可能性もある
         else # ただ蓄電池が減っていくだけ
           diff = @battery - @buy_target
           asksell = diff - crnt_demand - next_demand + crnt_solar + next_solar # 次の消費量も踏まえて抑えめに売る
           asksell = 0.0 if asksell < 0.0
         end
       end
     end 
   when 1 
   #########################################################################################
   # 時間別の最良と思われる購入時間及び販売時間から決定()
   end
   askbuy *= beta
   askbuy = 0.0 if askbuy < 0.0
   askbuy = @max_strage - @battery if @battery + askbuy > @max_strage
   asksell *= @sell_times[time]
   asksell = 0.0 if asksell < 0.0
   asksell = askbuy if @battery - asksell + askbuy < 0.0
   asksell = 0.0 if @battery <= 0.0 # 最終手段
   askbuy = max_transition if askbuy > max_transition
   asksell = max_transition if asksell > max_transition
   p asksell
   return askbuy,asksell 
 end

 #
 #
 def buy_and_sell_with_price demand, solar
   
 end

 # 現在時刻のみ見る場合の戦略
 def buy_power_2 d0, s0
  max_buy = 500.0
  if d0 > s0
   if @battery - (d0 - s0) > @target
    @battery = @battery - (d0 - s0)
    sell_power_2
    return 0.0
   else
    value =  (@target - (@battery - (d0 - s0)))*1.2
    value = value > max_buy ? max_buy : value
    @battery = @battery - d0 + value
    return value
   end
  else
   @battery =  @battery + (s0 - d0) < @max_strage ? @battery + (s0 - d0) : @max_strage
   sell_power_2
   return 0.0
  end
 end

 # d0: current_demand
 # d1: next_demand
 # s0: current solar value
 # s0: next solar value
 def buy_power_3 d0, d1, s0, s1
  next_condition = @battery - (d0 - s0) - (d1 - s1) # 未来の条件式
  crnt_condition = @battery - (d0 - s0) # 現在の条件式
  result = 0.0 # 結果値

  if crnt_condition < @target # 現時点で目標値よりバッテリー残量が少ないとき
   if next_condition < @target # 次の時刻でも目標値が達成できないとき
    # 達成できなくなる分の電力を買っておく
    if @target - next_condition > 500.0 # １５分に受け取れる電力量は500wと想定する
     result = 500.0
    else
     result = @target - next_condition
    end
    # 買った分で最大容量を超えてしまったときは超えないようにする
    next_battery = crnt_condition + result # 次の時刻でのバッテリー残量予測
    result = next_battery > @max_strage ? result - (next_battery - @max_strage) : result
   else # 次の時刻では目標値が達成できるとき
    # 買わない 売るかどうかは保留したほうがいい？ただし0にはしないようにする
    result = 1.0 if crnt_condition == 0.0
    sell_power_2
   end
  else # 現時点では目標値は達成しているとき
   if next_condition < @target # 次の時刻で目標値が達成できない
    # 達成できなくなる分の電力を買っておく
    if @target - next_condition > 500.0 # １５分に受け取れる電力量は500wと想定する
     result = 500.0
    else
     result = @target - next_condition
    end
    next_battery = crnt_condition + result # 次の時刻でのバッテリー残量予測
    result = next_battery > @max_strage ? result - (next_battery - @max_strage) : result
   else # 次の時刻でも目標値が達成できるとき
    # Don't buy power.
    # むしろ売る
    sell_power_2
   end
  end
  @battery = crnt_condition + result # バッテリー残量の状態遷移
  @battery = @max_strage if @battery > @max_strage
  return result
 end

 # 買う相手先の選択
 def select_target id
  
 end

 # Sell 2
 def sell_power2nd d1, s1
  over_condition = @battery - @sell_target < 500.0
  result = 0.0
  if over_condition
    return result
  else
   result = @battery - @sell_target - 500.0 > 500.0 ? 500.0 : @battery - @sell_target - 500.0
   @battery = @battery - result
   return result 
  end
 end

 # 電力を売る
 def sell_power cnt=-1
  over_condition = @battery - @sell_target  <= 500.0 # 500w以上売ろうとするのをキャンセル

  result = 0.0
  if over_condition
    if @battery - @sell_target < @buy_target # 売るときの目標蓄電量が買う時の目標蓄電量より下回らないければ売る
      return result # 0.0
    else
      result =  (@battery - @sell_target) 
      result *= @weights[cnt] if cnt != -1
      @battery = @battery - result
      return result
    end
  else
   result = 500.0
   #result = @battery - @sell_target - 500.0 > 500.0 ? 500.0 : @battery - @sell_target - 500.0
   result = result * @weights[cnt] if cnt != -1
   @battery = @battery - result
   return result 
  end
 end

 # 予測値考慮
 def sell_power_2
  @sells = sell_power
  return @sells
 end

 # 時間をすすめる
 def next_time time
  #@clock += 1
 end

 # 1日の初期化
 def init_date
  #@clock = 0
  self.csv_out
  @filter.particles_zero unless @filter.nil?
  train_data_per_day
  ## 学習時に用いる一時退避用の配列初期化
  @buy_times = Array.new((1440/TIMESTEP),0.0) 
  @sell_times = Array.new((1440/TIMESTEP),0.0)
  @oneday_buys = Array.new((1440/TIMESTEP), 0.0) # 一日の買った電力をタイプステップごとで記録し学習
  @oneday_sells = Array.new((1440/TIMESTEP), 0.0) # 一日の売った電力をタイムステップごとで記録し学習
  @oneday_battery = Array.new((1440/TIMESTEP), 0.0) 
  #@filter.init_data if !@filter.nil? && !@filter.eql?("normal")
 end

 ##
 # 需要の学習データから平均的な一日の需要データを取得
 def smooth_demand_train_data
   demand_trains = @trains[:demands][@weather]
   chunk = demand_trains.size/(1440/TIMESTEP)
   result = Array.new((1440/TIMESTEP),0.0)
   return result if chunk==0
   (0..(1440/TIMESTEP-1)).each do |cnt|
     sum = 0.0
     for i in 0..chunk-1
       index = i * (1440/TIMESTEP)
       sum += demand_trains[cnt+index]
     end
     result[cnt] = (sum / chunk.to_f)
   end
   return result
 end

 ##
 # 発電量の学習データから平均的な一日の需要データを取得
 def smooth_solar_train_data
   solar_trains = @trains[:solars][@weather]
   chunk = solar_trains.size/(1440/TIMESTEP)
   result = Array.new(1440/TIMESTEP,0.0)
   return result if chunk==0
   (0..(1440/TIMESTEP-1)).each do |cnt|
     sum = 0.0
     for i in 0..chunk-1
       index = i * (1440/TIMESTEP)
       sum += solar_trains[cnt+index]
     end
     result[cnt] = (sum / chunk.to_f)
   end
   return result
 end

 ###
 #
 def smooth_buy_train_data
   trains = @trains[:buys][@weather]
   chunk = trains.size/(1440/TIMESTEP)
   result = Array.new(1440/TIMESTEP,0.0)
   return result if chunk==0
   (0..(1440/TIMESTEP-1)).each do |cnt|
     sum = 0.0
     for i in 0..chunk-1
       index = i * (1440/TIMESTEP)
       sum += trains[cnt+index]
     end
     result[cnt] = (sum / chunk.to_f)
   end
   return result
 end

 ###
 #
 def smooth_sell_train_data
   sells = @trains[:sells][@weather]
   chunk = sells.size/(1440/TIMESTEP)
   result = Array.new(1440/TIMESTEP,0.0)
   return result if chunk==0
   (0..(1440/TIMESTEP-1)).each do |cnt|
     sum = 0.0
     for i in 0..chunk-1
       index = i * (1440/TIMESTEP)
       sum += sells[cnt+index]
     end
     result[cnt] = (sum / chunk.to_f)
   end
   return result
 end

 ###
 #
 def smooth_p_purchase_price
   trains = @trains[:p_purchase_price][@weather]
   chunk = trains.size/(1440/TIMESTEP)
   result = Array.new(1440/TIMESTEP,0.0)
   return result if chunk==0
   (0..(1440/TIMESTEP-1)).each do |cnt|
     sum = 0.0
     for i in 0..chunk-1
       index = i * (1440/TIMESTEP)
       sum += trains[cnt+index]
     end
     result[cnt] = (sum / chunk.to_f)
   end
   return result

 end

 ##
 #
 def smooth_p_sell_price
   trains = @trains[:p_sell_price][@weather]
   chunk = trains.size/(1440/TIMESTEP)
   result = Array.new(1440/TIMESTEP,0.0)
   return result if chunk==0
   (0..(1440/TIMESTEP-1)).each do |cnt|
     sum = 0.0
     for i in 0..chunk-1
       index = i * (1440/TIMESTEP)
       sum += trains[cnt+index]
     end
     result[cnt] = (sum / chunk.to_f)
   end
   return result
 end

 def smooth_battery_train_data
   trains = @trains[:battery][@weather]
   chunk = trains.size/(1440/TIMESTEP)
   result = Array.new(1440/TIMESTEP,0.0)
   return result if chunk==0
   (0..(1440/TIMESTEP-1)).each do |cnt|
     sum = 0.0
     for i in 0..chunk-1
       index = i * (1440/TIMESTEP)
       sum += trains[cnt+index]
     end
     result[cnt] = (sum / chunk.to_f)
   end
   return result
 end
 
 
 #####
 # 天気予報のチェック
 #  ある１位日の総発電量から天候をセットする
 #  - sum_solar: ある一日の総発電量 
 def switch_weather_for_pf sum_solar
  @filter.eval_weather sum_solar if !@filter.nil?
  if SUNNY_BORDER < sum_solar
   @weather = SUNNY
  elsif CLOUDY_BORDER < sum_solar
   @weather = CLOUDY
  else
   @weather = RAINY
  end
  ####
  #### select_time_and_value_to_buy # 夜間におよその購入量と蓄電量を概算する 
 end

 ###
 # recieve_msg
 # @msg: メッセージ
 def recieve_msg msg
   ds = msg.split(",")
   reply_to = ds[0].gsub("id:","")
   sell = 0.0
   buy = 0.0
   ds.each do |pay|
     case pay
     when /^buy:.*/
       sell = pay.gsub('buy:','').to_f ## buyは電力会社が買った量
     when /^sell:.*/
       buy = pay.gsub('sell:','').to_f ## sellは電力会社が売った量
     end
   end
   solar = @solars[@clock[:step]]
   demand = @demands[@clock[:step]]
   #ap @battery
   self.update_battery sell,buy,demand,solar
   @oneday_buys[@clock[:step]] = buy
   @oneday_sells[@clock[:step]] = sell
 end

 ## 
 # 10日周期で保存
 def csv_out
   cnt = @clock[:day] + 1
   if cnt % 10 == 0
     filepath = "#{File.expand_path File.dirname __FILE__}/../result/#{@id}/result_#{cnt}.csv"
     file = open(filepath,'w')
     file.write("buy,battery,predict,real,sell,weather,demand\n")
     @simdatas.each {|data|
       file.write "#{data[:buy]},#{data[:battery]},#{data[:predict]},#{data[:real]},#{data[:sell]},#{data[:weather]},#{data[:demand]}\n"
     }
     file.close
     @simdatas = []
   end
 end

 ### バッテリー更新
 def update_battery sell, buy, demand, solar
   @battery = @battery - sell - demand + solar + buy
 end

 private

 #####
 # chunk分に学習していく
 #
 def train_data_per_day
  @trains[:demands][@weather].concat @demands.clone
  @trains[:solars][@weather].concat @solars.clone
  @trains[:buys][@weather].concat @oneday_buys.clone
  @trains[:sells][@weather].concat @oneday_sells.clone
  @trains[:battery][@weather].concat @oneday_battery.clone

  if @chunk_size * (1440/TIMESTEP) < @trains[:demands][@weather].size
   @trains[:demands][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1)
   @trains[:solars][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1)
   @trains[:buys][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1)
   @trains[:sells][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1)
   @trains[:battery][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1)
  end

  ## 価格のデータを学習
  ppp = []
  psp = []
  @my_contractor.trains[@weather].each do |data|
    psp << data[:sell_price]
    ppp << data[:purchase_price]
  end

  @trains[:p_purchase_price][@weather].concat ppp.clone ## こいつのデータはどんどん肥大
  @trains[:p_sell_price][@weather].concat psp.clone ## こいつのデータはどんどん肥大
  if @chunk_size * (1440/TIMESTEP) < @trains[:p_purchase_price][@weather].size
    @trains[:p_purchase_price][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1) 
    @trains[:p_sell_price][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1) 
  end
 end

 #####
 # 朝5時に発動する
 def get_trains_power_average_from_time time
  sum_power = 0.0
  size = 15 * (60/TIMESTEP) - 1
  if time < 15*(60/TIMESTEP) && @trains[:solars][@weather].size > 0
   for index in time..size
    demand = @trains[:demands][@weather][index]
    solar = @trains[:solars][@weather][index]
    sum_power = sum_power + solar - demand
   end
   return sum_power
  end
  return 0.0
 end

 # フィルターの初期化
 def filter_init type
  case type
  when 'pf'
   return @filter = ParticleFilter.new 
  when 'normal'
   return @filter = 'normal'
  when 'none'
   return nil
  end
  return nil
 end

 ## msgの送信
 def send_message msg
  @my_contractor.recieve_msg msg
 end

 ##
 # ステップとtime、天候が等しい学習データを検索
 # @time: step
 def search_q_trains time
   @trains[:q_trains].select{|x| x[:step] == time && x[:weather] == @weather }
 end

end
