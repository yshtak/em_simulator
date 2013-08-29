# coding: utf-8 
require 'celluloid/autostart'
require "#{File.expand_path File.dirname __FILE__}/../filter/06_particle_filter"
require "#{File.expand_path File.dirname __FILE__}/../config/simulation_data"
#========================================================
#
# Home Agent v6.0
# 2013-07-27
#  - 新しいParticle Filterを導入
# 2013-07-30
#  - 夜間に電力をまとめて買う戦略の導入
# 2013-08-18
#  - ActorModelの導入 mailboxでメッセージを受け取るよう
#  に設定
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
   max_strage: 5000.0, # 蓄電容量(Wh)
   target: 500.0, # 目標蓄電量(Wh)
   buy_target_ratio: 0.3, # 30%
   sell_target_ratio: 0.8, # 40%
   solars: [], # 15分毎の1日の電力発電データ
   demands: [], # 15分毎の1日の需要データ
   address: "unknown",
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
  @my_contractor = config[:contractor] # ポインター受け渡し
  @chunk_size = config[:chunk_size] # 学習データサイズ
  @midnight_ratio = config[:midnight_ratio] 
  @midnight_interval = config[:midnight_interval]
  @midnight_strategy = config[:midnight_strategy]
  @max_strage = config[:max_strage]
  @battery = 2000.0
  @address = config[:address]
  @weather = -1 # none 
  @filter = filter_init config[:filter]
  @target = config[:target] # 目標充電量
  @buy_target = @max_strage * config[:buy_target_ratio] # 買いの購入の意思決定閾値（蓄電量）
  @sell_target = @max_strage * config[:sell_target_ratio] # 買いの購入の意思決定閾値（蓄電量）
  @solars = config[:solars]
  @demands = config[:demands]
  @clock = {:step => 0, :day => 0}
  #@sells = (0..SIM_INTERVAL-1).map{|i| 0.0}
  @sells = 0.0
  # 学習データ
  @trains={
   demands:{
    SUNNY => [],
    RAINY => [],
    CLOUDY => []
   },
   solars:{
    SUNNY => [],
    RAINY => [],
    CLOUDY => []
   },
   p_sell_price:{
    SUNNY => [],
    RAINY => [],
    CLOUDY => []
   },
   p_purchase_price:{
    SUNNY => [],
    RAINY => [],
    CLOUDY => []
   },
   ## format
   # {weather: 天候, step: 時刻 , solar: 発電量 , demand: 需要 , buy_price: 買値 ,sell_price: 売値 , battery: バッテリー残量%(切り捨て) }
   # {buy: , sell: , }
   q_trains: [] ## Q学習用データ(逐次的に蓄積されていく)
  }
  @buy_times = Array.new((1440/TIMESTEP),0.0) # 一日の間に時間別で購入する量の配列
  @sell_times = Array.new((1440/TIMESTEP),0.0) # 一日の間に時間別に販売する量の配列
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

 ### version 0.7 ##########################################
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
   timeline = ""
   results = [] # 買った電力量
   bs = [] # 蓄電池の状況
   predicts = [] # 予測値(実験用)
   reals = []
   sells = [] # simdatas のsellsのポインター
   buys = []
   demands = []
   simdatas = {buy: results, battery: bs, predict: predicts, real: reals, sell: sells, demand: demands} # 結果
   simdata = {}
   if @filter.nil? # Filter使わないとき
    if cnt > @midnight_interval*(60/TIMESTEP)  && cnt < 23*(60/TIMESTEP) # タイムステップ（最初の1時間と最後の1時間を除く）
     crnt_solar = @solars[cnt]
     crnt_demand = @demands[cnt]
     temp_battery = @battery
     power_value = buy_power_2(crnt_demand,crnt_solar) # 予測考慮なし

     results << power_value
     #sells << sell_value
     if @buy_times[0] != 0.0 # 買う戦略をした時のみ発動
      @sells = 0.0 if @battery > @target && cnt < 13*(60/TIMESTEP) && @midnight_strategy
     end
     sells << @sells
     predicts << crnt_solar
     reals << crnt_solar
     #### 描画部分
     #if power_value != 0.0
     # timeline += " o"
     #elsif @sells != 0.0
     # timeline += " x"
     #else
     # timeline += " _"
     #end
     #print "\e[33m購入状況:#{timeline}\e[0m\r"

    else # 最初の1時間と最後の一時間
     #@filter.train_per_step @solars[cnt] # 学習はする（つじつま合わせ）
     if @midnight_strategy # 夜間戦略あり
      reals << @solars[cnt]
      predicts << @solars[cnt]
      results << @buy_times[cnt] # 予め買う予定の電力量の購入
      demand = @demands[cnt] # 消費量
      @battery += (@buy_times[cnt] - demand) # Battery更新
      sells << 0.0
      ### 描画部分
      #timeline = @buy_times[cnt] != 0 ? timeline + " o" : timeline + " _"
      #print "\e[33m購入状況:#{timeline}\e[0m\r"
     else # 夜間戦略なし
      crnt_solar = @solars[cnt]
      predicts << crnt_solar
      reals << crnt_solar
      demand = @demands[cnt] # 消費量
      demands << demand
      if @battery - demand < @target # バッテリー容量が目標値を下回るとき
       results << @target - @battery + demand # 目標値になるように電力を買う
       sells << 0.0
       @battery = @target
      else
       results << 0.0
       sells << sell_power 
      end
      ### 描画部分
      #if @battery - demand < @target
      # timeline += " o"
      #elsif @sells > 0.0
      # timeline += " x"
      #else
      # timeline += " _"
      #end
      #print "\e[33m購入状況:#{timeline}\e[0m\r"
     end
    end
   elsif @filter.eql?("normal") # 平均した曲線モデルで予測する場合
    if cnt > @midnight_interval*(60/TIMESTEP)  && cnt < 23*(60/TIMESTEP) # タイムステップ（最初の1時間と最後の1時間を除く）
     crnt_solar = @solars[cnt]
     #next_solar = @weather_models[@weather][cnt+1]
     next_solar = @filter.ave_models[@weather][cnt+1]
     #next_solar = @weather_model[cnt+1]
     crnt_demand = @demands[cnt]
     next_demand = @demands[cnt+1]

     #power_value = buy_power(crnt_demand,next_demand,crnt_solar,next_solar) # 予測考慮する
     power_value,sell_value = buy_and_sell_power_2step(crnt_demand,next_demand,crnt_solar,next_solar,cnt) # 予測考慮する
     #power_value = buy_power_3(crnt_demand,next_demand,crnt_solar,next_solar) # 予測考慮する
     #sell_value = sell_power # 余剰電力を売る

     results << power_value
     sells << @sells
     #sells << sell_value
     predicts << next_solar
     reals << crnt_solar
    else
     next_solar = @filter.ave_models[@weather][cnt]
     #next_solar = @weather_models[@weather][cnt]
     #next_solar = @weather_model[cnt+1]
     predicts << next_solar
     reals << @solars[cnt]
 
     if @battery < @target
      results << @target - @battery
      sells << 0.0 
      @battery = @target
     else
      results << 0.0
      sells << sell_power 
     end

    end 
   else # Particle Filter を使った場合
    if cnt > @midnight_interval*(60/TIMESTEP)  && cnt < 23*(60/TIMESTEP) # タイムステップ（最初の1時間と最後の1時間を除く）
     crnt_solar = @solars[cnt]
     #next_solar = @filter.next_value_predict(crnt_solar, cnt)
     next_solar = @filter.predict_next_value(crnt_solar, cnt)
     @filter.train_per_step crnt_solar
     crnt_demand = @demands[cnt]
     next_demand = @demands[cnt+1]
     simdata[:demand] = crnt_demand
     #power_value = buy_power(crnt_demand,next_demand,crnt_solar,next_solar) # 予測考慮する（通常版）
     power_value, sell_value = buy_and_sell(crnt_demand,next_demand,crnt_solar,next_solar,cnt,0) # 予測考慮する
     #power_value, sell_value = buy_and_sell_power_2step(crnt_demand,next_demand,crnt_solar,next_solar,cnt) # 予測考慮する
     #power_value, sell_value = buy_and_sell_power(crnt_demand,next_demand,crnt_solar,next_solar,cnt) # 予測考慮する
     #power_value = buy_power_2step(crnt_demand,next_demand,crnt_solar,next_solar,cnt) # 予測考慮する
     #power_value = buy_power_3(crnt_demand,next_demand,crnt_solar,next_solar) # 予測考慮する
     #sell_value = sell_power # 余剰電力を売る

     simdata[:buy] = power_value
     #sells << sell_value
     #### 朝のうちに買っておいた蓄電量をあまり売らない（買ってから蓄電池目標量を下回った時だけ）
     #if @buy_times[0] != 0.0 # 買う戦略をした時のみ発動
     # if @battery > @target && cnt < 10*(60/TIMESTEP) && @midnight_strategy
     #  #@battery += @sells # 売ろうとした電力を回復
     #  sells_value = 0.0 # やっぱり売らない
     # end
     #end

     simdata[:sell] = sell_value
     simdata[:predict] = next_solar
     simdata[:real] = crnt_solar
     #results << (power_value - @battery > 0.0 ? power_value - @battery : 0.0)
     #### 描画部分
     #if power_value != 0.0
     # timeline += " o"
     #elsif @sells != 0.0
     # timeline += " x"
     #else
     # timeline += " _"
     #end
     #print "\e[33m購入状況:#{timeline}\e[0m\r"
     send_message "id:#{@id},buy:#{power_value},sell:#{sell_value}" 
    else # 夜中と早朝の戦略
     @filter.train_per_step @solars[cnt] # 学習はする（つじつま合わせ）
     if @midnight_strategy && @trains[:p_sell_price][@weather].size == 0 # 夜間の戦略（かつ学習データがない場合）
      simdata[:real] = @solars[cnt]
      simdata[:predict] = @solars[cnt]
      demand = @demands[cnt] # 消費量
      simdata[:demand] = demand
      #@battery += (@buy_times[cnt]-demand) # Battery更新
      @buy_times[cnt] = @max_strage - @battery + @buy_times[cnt] if @battery > @max_strage
      #@battery = @max_strage if @battery > @max_strage
      simdata[:buy] = @buy_times[cnt] # 予め買う予定の電力量の購入
      sell_value = @battery - @sell_times[cnt] * 20.0 < 0.0 ? 0.0 : @sell_times[cnt] * 20.0
      simdata[:sell] = 0.0
      ### 描画部分
      #timeline = @buy_times[cnt] != 0 ? timeline + " o" : timeline + " _"
      #print "\e[33m購入状況(#{(100*@battery/@max_strage).to_i}%):#{timeline}\e[0m\r"
      send_message "id:#{@id},buy:#{@buy_times[cnt]},sell:#{sell_value}"
     else # 夜間戦略なし
      next_solar = @filter.predict_next_value(@solars[cnt], cnt)
      simdata[:predict] = next_solar
      simdata[:real] = @solars[cnt]
      simdata[:solar] = @solars[cnt]
      demand = @demands[cnt] # 消費量
      simdata[:demand] = demand
      if @battery - demand < @target
       simdata[:buy] = @target - @battery + demand
       simdata[:sell] = 0.0
       #@battery = @target 
      else
       results << 0.0
       simdata[:buy] = 0.0
       sell_value = sell_power
       simdata[:sell] = sell_value
      end
      #@battery -= demand
      ### 描画部分
      #if @battery - demand < @target
      # timeline += " o"
      #elsif @sells > 0.0
      # timeline += " x"
      #else
      # timeline += " _"
      #end
      #print "\e[33m購入状況(#{(100*@battery/@max_strage).to_i}%):#{timeline}\e[0m\r"
      send_message "id:#{@id},buy:#{power_value},sell:#{sell_value}" 
     end
    end
   end
   ##bs << @battery
   #print "\n"
   simdata[:weather] = @weather
   simdata[:battery] = @battery
   @simdatas << simdata
   #### ここではまだ完全にbatteryが更新されない
   return simdatas
 end

 # 
 def decide_sell_power
 end 

 ###########################################################
 #
 #
 # v0.8
 ###########################################################
  
 # 報酬関数
 # dataformat: 
 #  {weather: 天候, step: 時刻 , buy: 購入量 , sell: 販売量 , buy_price: 買値 ,sell_price: 売値 , battery: バッテリー残量%(切り捨て) }
 def reward step
   datas = []
   (step+1..(1440/TIMESTEP)-1).each{|time| datas.concat(self.search_q_trains(time))}
   reward = 0.0
   # 報酬計算
   datas.each{|data|
     reward += data[:sell] * data[:sell_price] - data[:buy] * data[:buy_price] ## 収益
     #data[:solar]
     #data[:demand]
     #data[:sell_price]
     #data[:buy_price]
     #data[:battery]
   }
 end

 ###########################################################
 
 # 一日の行動をする
 def date_action
  timeline = ""
  results = [] # 買った電力量
  bs = [] # 蓄電池の状況
  predicts = [] # 予測値(実験用)
  reals = []
  sells = [] # simdatas のsellsのポインター
  buys = []
  demands = []
  simdatas = {buy: results, battery: bs, predict: predicts, real: reals, sell: sells} # 結果
  for cnt in 0..(1440/TIMESTEP-1) do
   if @filter.nil? # Filter使わないとき
    if cnt > @midnight_interval*(60/TIMESTEP)  && cnt < 23*(60/TIMESTEP) # タイムステップ（最初の1時間と最後の1時間を除く）
     crnt_solar = @solars[cnt]
     crnt_demand = @demands[cnt]
     temp_battery = @battery
     power_value = buy_power_2(crnt_demand,crnt_solar) # 予測考慮なし
     
     #sell_value = sell_power # 余剰電力を売る

     #if (@weather == SUNNY || @weather == CLOUDY ) && cnt < 15*(60/TIMESTEP)# もし晴れだった場合
     # a = get_trains_power_average_from_time cnt
     # if a + temp_battery > @target
     #  power_value = 0.0
     # end
     #end

     results << power_value
     #sells << sell_value
     if @buy_times[0] != 0.0 # 買う戦略をした時のみ発動
      @sells = 0.0 if @battery > @target && cnt < 13*(60/TIMESTEP) && @midnight_strategy
     end
     sells << @sells
     predicts << crnt_solar
     reals << crnt_solar
     #### 描画部分
     if power_value != 0.0
      timeline += " o"
     elsif @sells != 0.0
      timeline += " x"
     else
      timeline += " _"
     end
     print "\e[33m購入状況:#{timeline}\e[0m\r"

    else # 最初の1時間と最後の一時間
     #@filter.train_per_step @solars[cnt] # 学習はする（つじつま合わせ）
     if @midnight_strategy # 夜間戦略あり
      reals << @solars[cnt]
      predicts << @solars[cnt]
      results << @buy_times[cnt] # 予め買う予定の電力量の購入
      demand = @demands[cnt] # 消費量
      @battery += (@buy_times[cnt] - demand) # Battery更新
      sells << 0.0
      ### 描画部分
      timeline = @buy_times[cnt] != 0 ? timeline + " o" : timeline + " _"
      print "\e[33m購入状況:#{timeline}\e[0m\r"
     else # 夜間戦略なし
      crnt_solar = @solars[cnt]
      predicts << crnt_solar
      reals << crnt_solar
      demand = @demands[cnt] # 消費量
      if @battery - demand < @target # バッテリー容量が目標値を下回るとき
       results << @target - @battery + demand # 目標値になるように電力を買う
       sells << 0.0
       @battery = @target
      else
       results << 0.0
       sells << sell_power 
      end
      ### 描画部分
      if @battery - demand < @target
       timeline += " o"
      elsif @sells > 0.0
       timeline += " x"
      else
       timeline += " _"
      end
      print "\e[33m購入状況:#{timeline}\e[0m\r"
     end
    end
   elsif @filter.eql?("normal") # 平均した曲線モデルで予測する場合
    if cnt > @midnight_interval*(60/TIMESTEP)  && cnt < 23*(60/TIMESTEP) # タイムステップ（最初の1時間と最後の1時間を除く）
     crnt_solar = @solars[cnt]
     #next_solar = @weather_models[@weather][cnt+1]
     next_solar = @filter.ave_models[@weather][cnt+1]
     #next_solar = @weather_model[cnt+1]
     crnt_demand = @demands[cnt]
     next_demand = @demands[cnt+1]

     #power_value = buy_power(crnt_demand,next_demand,crnt_solar,next_solar) # 予測考慮する
     power_value,sell_value = buy_and_sell_power_2step(crnt_demand,next_demand,crnt_solar,next_solar,cnt) # 予測考慮する
     #power_value = buy_power_3(crnt_demand,next_demand,crnt_solar,next_solar) # 予測考慮する
     #sell_value = sell_power # 余剰電力を売る

     results << power_value
     sells << sell_value
     #sells << sell_value
     predicts << next_solar
     reals << crnt_solar
    else
     next_solar = @filter.ave_models[@weather][cnt]
     #next_solar = @weather_models[@weather][cnt]
     #next_solar = @weather_model[cnt+1]
     predicts << next_solar
     reals << @solars[cnt]
 
     if @battery < @target
      results << @target - @battery
      sells << 0.0 
      @battery = @target
     else
      results << 0.0
      sells << sell_power 
     end

    end 
   else # Particle Filter を使った場合
    if cnt > @midnight_interval*(60/TIMESTEP)  && cnt < 23*(60/TIMESTEP) # タイムステップ（最初の1時間と最後の1時間を除く）
     crnt_solar = @solars[cnt]
     #next_solar = @filter.next_value_predict(crnt_solar, cnt)
     next_solar = @filter.predict_next_value(crnt_solar, cnt)
     @filter.train_per_step crnt_solar
     crnt_demand = @demands[cnt]
     next_demand = @demands[cnt+1]
     #power_value = buy_power(crnt_demand,next_demand,crnt_solar,next_solar) # 予測考慮する（通常版）
     #temp_battery = @battery # 前の蓄電量を退避(買いすぎの対処
     power_value,sell_value = buy_and_sell_power_2step(crnt_demand,next_demand,crnt_solar,next_solar,cnt) # 予測考慮する
     #power_value = buy_power_3(crnt_demand,next_demand,crnt_solar,next_solar) # 予測考慮する
     #sell_value = sell_power # 余剰電力を売る

     # 12時になるまではなるべく待機
     #if cnt < 11*(60/TIMESTEP)# もし晴れだった場合
     # a = get_trains_power_average_from_time cnt
     # if a + temp_battery > @target
     #  power_value = 0.0
     # end
     #end

     results << power_value
     #sells << sell_value
     #### 朝のうちに買っておいた蓄電量をあまり売らない（買ってから蓄電池目標量を下回った時だけ）
     if @buy_times[0] != 0.0 # 買う戦略をした時のみ発動
      if @battery > @target && cnt < 10*(60/TIMESTEP) && @midnight_strategy
       #@battery += @sells # 売ろうとした電力を回復
       @sells = 0.0 # やっぱり売らない
      end
     end
     sells << sell_value 
     predicts << next_solar
     reals << crnt_solar
     #results << (power_value - @battery > 0.0 ? power_value - @battery : 0.0)

     #### 描画部分
     if power_value != 0.0
      timeline += " o"
     elsif @sells != 0.0
      timeline += " x"
     else
      timeline += " _"
     end
     print "\e[33m購入状況(#{(100*@battery/@max_strage).to_i}%):#{timeline}\e[0m\r"
     ### 電力事業所にメールを送る
     ##@my_contractor.mailbox << "buy:#{power_value},sell:#{@sells}"
     ##@my_contractor.dump
     #@my_contractor.recieve_msg "buy:#{power_value},sell:#{@sells}"
     send_message "buy:#{power_value},sell:#{@sells}" 
    else # 夜中と早朝の戦略
     @filter.train_per_step @solars[cnt] # 学習はする（つじつま合わせ）
     if @midnight_strategy # 夜間の戦略有り
      reals << @solars[cnt]
      predicts << @solars[cnt]
      demand = @demands[cnt] # 消費量
      @battery += (@buy_times[cnt]-demand) # Battery更新
      @buy_times[cnt] = @max_strage - @battery + @buy_times[cnt] if @battery > @max_strage
      @battery = @max_strage if @battery > @max_strage
      results << @buy_times[cnt] # 予め買う予定の電力量の購入
      sells << 0.0
      ### 描画部分
      timeline = @buy_times[cnt] != 0 ? timeline + " o" : timeline + " _"
      print "\e[33m購入状況(#{(100*@battery/@max_strage).to_i}%):#{timeline}\e[0m\r"
     else # 夜間戦略なし
      next_solar = @filter.predict_next_value(@solars[cnt], cnt)
      predicts << next_solar
      reals << @solars[cnt]
      demand = @demands[cnt] # 消費量
      if @battery - demand < @target
       results << @target - @battery + demand
       sells << 0.0
       @battery = @target 
      else
       results << 0.0
       sells << sell_power # Batteryも更新される
      end
      ### 描画部分
      if @battery - demand < @target
       timeline += " o"
      elsif @sells > 0.0
       timeline += " x"
      else
       timeline += " _"
      end
      print "\e[33m購入状況(#{(100*@battery/@max_strage).to_i}%):#{timeline}\e[0m\r"
      send_message "buy:#{power_value},sell:#{@sells}" 
     end
    end
   end
   bs << @battery
  end
  #p predicts[45]
  #p reals[45]
  #return [results, bs]
  print "\n"
  simdatas[:weather] = @weather
  return simdatas
 end

 ###
 # 行動価値関数
 def tender_buy_and_sell
    
 end

 ###
 # 電力販売戦略
 def sell_tender

 end

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
  @buy_times = @buy_times.map{|data| 0.0}
  train_data_per_day
  #@filter.init_data if !@filter.nil? && !@filter.eql?("normal")
 end

 ## 夜間にチェックする
 # 最適解の計算も行う
 def select_time_and_value_to_buy
  cnt = 0
  chunk = 0
  train_demands = @trains[:demands][@weather]
  sum_demand = 0.0
  while train_demands.size > cnt 
   sum_demand += @trains[:demands][@weather][cnt]
   cnt += 1
   if cnt % (1440/TIMESTEP) == 0 && cnt / (1440/TIMESTEP) != 0
    chunk += 1
   end
  end

  sum_demand /= chunk ## 次の日の電力需要

  sum_solar = @trains[:solars][@weather].inject(0.0){|acc, x| acc+=x}
  #sum_demand = @demands.inject(0.0){|acc,x| acc+=x}
  sum_solar /= chunk
  ##################################################################
  ## 夜間の電力購入の戦略
  ##
  ##@may_get_solar = sum_solar / (@trains[:solars][@weather].size / (1440/TIMESTEP))
  buy_interval = @trains[:p_sell_price][@weather].size > 0 ? (@weather == SUNNY ? 12 : 24) : MIDNIGHT_INTERVAL 
  per_demand = ->(value) {(value/(buy_interval*(60/TIMESTEP)))} # ４時間分割する方程式
  
  one = 0.0
  if sum_solar - sum_demand > 0.0 && train_demands.size > 0 && @trains[:solars][@weather].size > 0# 次の日の発電量と需要の差が
   # 買わない
   midnight_demand = 0.0
   for index in (0..(buy_interval*(60/TIMESTEP)-1)) do
    tmp_de = 0.0
    for j in (0..chunk-1) do
     tmp_de += train_demands[index + (1440/TIMESTEP)*j]
    end
    midnight_demand += tmp_de/chunk if chunk != 0
   end
   tmp_buy = midnight_demand + @max_strage * @midnight_ratio - @battery
   #ap "\t夜間に購入する電力量：#{tmp_buy}"
   #tmp_buy =  @max_strage * @midnight_ratio - @battery
   one = per_demand.call tmp_buy # 四時間分割
  else ## 発電量が下回るとき（主に雨とか曇りに起きやすい）
   #if @battery + (sum_demand - sum_solar ) < @max_strage * @midnight_ratio # 最大容量を超えないとき
    #tmp_buy = (sum_demand - sum_solar)
    #one = per_demand.call tmp_buy # ４時間分割
   #else # 最大容量を超えるとき 
    #### 深夜N時間の消費量総和と購入する塩梅で調整
    midnight_demand = 0.0
    for index in (0..(buy_interval*(60/TIMESTEP)-1)) do
     tmp_de = 0.0
     for j in (0..chunk-1) do
      tmp_de += train_demands[index + (1440/TIMESTEP)*j]
     end
     midnight_demand += tmp_de/chunk if chunk != 0
    end
    tmp_buy = midnight_demand + @max_strage * @midnight_ratio - @battery
    #ap "\t夜間に購入する電力量：#{tmp_buy}"
    #tmp_buy =  @max_strage * @midnight_ratio - @battery
    one = per_demand.call tmp_buy # 四時間分割
   #end
  end
  #print "\t \e[32m今日の夜間の購入量情報：\n"
  #print "\t >> 予測需要量：#{sum_demand}\n\t >> 予測発電量：#{sum_solar}\n\t >> ワンステップごとの購入量：#{one}\n\e[0m" 
  
  # 買う時間を決定
  #well_buy_times = self.well_sort_buy_power # 前日の電力が安かった時間順序の配列取得(時間の配列)
  well_buy_times = self.optimum(self.smooth_p_sell_price, self.smooth_demand_train_data, self.smooth_demand_train_data,
                               "(1.0 / (price+0.01)) * demands[index] * (1.0/(0.01+solars[index]))") # 前日の電力の販売価格が安かった時間順序の配列取得(時間の配列)
  well_sell_times = self.optimum(self.smooth_p_purchase_price, self.smooth_demand_train_data, self.smooth_solar_train_data,
                                "price * (1.0 / (demands[index] + 0.01)) * solars[index] ") # 前日の電力の買取価格が高かった時間順序の配列取得(時間の配列)
  # TODO: 
  for i in 0..(buy_interval*((60/TIMESTEP))-1)
    if well_buy_times.size > 0
      ## 何時に買ったら安いかの計算(購入量は固定)
      @buy_times[well_buy_times[i]] = one * @weights[i] # 重み付き
    else
      if i*2-1 >= (buy_interval*((60/TIMESTEP))-1)
        # 夜間
        index = (((24*60/TIMESTEP)-4*buy_interval)) + i
        @buy_times[index] = one
      else
        ## 朝の購入
        @buy_times[i] = one 
      end
    end
  end

  ## sell_times
  for i in 0..@sell_times.size-1
    if well_sell_times.size > 0
      @sell_times[well_sell_times[i]] = @weights[i] # 重みを入れる
    end
  end

  #p @buy_times
  #well_buy_times = self.when_buy_power # 前日の電力が安かった時間順序の配列取得(時間の配列)
  #well_sell_times = self.when_sell_power # 前日の電力が安かった時間順序の配列取得(時間の配列)
  #p self.well_sort_sell_power # 前日の電力が安かった時間順序の配列取得(時間の配列)
 end

 ##
 # いつ電力
 # @prices: 任意の天気の過去１日分の販売価格または買取価格のデータ
 # @demands: 学習した需要のデータ
 # @solars: 学習した発電量のデータ
 # @score_eval: スコア関数
 def optimum prices, demands, solars, score_eval
   return (0..prices.size-1).to_a if prices[0].nan?
   condition = 500 # 一度に購入できる電力量は500w
   scores = [] # いつ購入したほうがいいかのスコア配列
   ### 正規化
   d_sum = (demands.inject(0.0){|sum,d| sum+=d}) 
   s_sum = (solars.inject(0.0){|sum, s| sum+=s}) 
   demands.map!{|demand| demand / d_sum }
   solars.map!{|solar| solar / s_sum }
   #sell_socres = [] # いつ販売したほうがいいかのスコア配列
   #p solars
   ## スコアを計算する（スコアは高ければ高いほど良い）
   prices.each_with_index{|price,index| 
     ## 価格・発電量が高いと買いたくなくなり、需要が高くなると買いたい
     scores << (eval "#{score_eval}") # スコア関数の適用
   }
   size = scores.size
   steps = (0..size-1).to_a
   steps.sort!{|i1,i2| scores[i2] <=> scores[i1]} # 降順
   #ap steps
   return steps
 end

 ##
 # 安かった時間の順番を配列で返すメソッド
 # return steps
 def well_sort_buy_power
   train = @trains[:p_sell_price][@weather]
   size = train.size
   steps = (0..size-1).to_a
   steps.sort!{|i1,i2| train[i1] <=> train[i2] }
   return steps
 end

 ##
 # 高かった買取価格の時間の順番の配列を返す
 # return steps
 def well_sort_sell_power
   train = @trains[:p_purchase_price][@weather]
   size = train.size
   steps = (0..size-1).to_a
   steps.sort!{|i1,i2| train[i2] <=> train[i1]}
   return steps
 end

 ##
 # 需要の学習データから平均的な一日の需要データを取得
 def smooth_demand_train_data
   demand_trains = @trains[:demands][@weather]
   chunk = demand_trains.size/(1440/TIMESTEP)
   result = Array.new((1440/TIMESTEP),0.0)
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
 def smooth_p_purchase_price
   solar_trains = @trains[:p_purchase_price][@weather]
   chunk = solar_trains.size/(1440/TIMESTEP)
   result = Array.new(1440/TIMESTEP,0.0)
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

 ##
 #
 def smooth_p_sell_price
   solar_trains = @trains[:p_sell_price][@weather]
   chunk = solar_trains.size/(1440/TIMESTEP)
   result = Array.new(1440/TIMESTEP,0.0)
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
  select_time_and_value_to_buy # 夜間におよその購入量と蓄電量を概算する 
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
  if @chunk_size * (1440/TIMESTEP) < @trains[:demands][@weather].size
   @trains[:demands][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1)
   @trains[:solars][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1)
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
  if 10 * (1440/TIMESTEP) < @trains[:p_purchase_price][@weather].size
    @trains[:p_purchase_price][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1) 
    @trains[:p_sell_price][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1) 
  end
 end

 #####
 # 朝5時に発動する
 #
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
