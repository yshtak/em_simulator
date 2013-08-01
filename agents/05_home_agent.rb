require "#{File.expand_path File.dirname __FILE__}/../filter/05_particle_filter"
require "#{File.expand_path File.dirname __FILE__}/../config/simulation_data"
#========================================================
#
# Home Agent v5.0
# 2013-07-27
#  - 新しいParticle Filterを導入
# 2013-07-30
#  - 夜間に電力をまとめて買う戦略の導入
#
#========================================================
class HomeAgent
 attr_accessor :strage, :target, :filter
 SIM_INTERVAL = 24 * 4 # 15分刻み
 include SimulationData

 def initialize cfg={}
  config = {
   filter: 'none', # 未来予測のためのフィルターのタイプ
   max_strage: 5000.0, # 蓄電容量(Wh)
   target: 2000.0, # 目標蓄電量(Wh)
   solars: [], # 15分毎の1日の電力発電データ
   demands: [], # 15分毎の1日の需要データ
   address: "unknown",
   limit_power: 500.0,
   chunk_size: 5,
   midnight_ratio: 0.8, # 夜間に購入する目標充電率
   midnight_strategy: true # 夜間戦略ありなし
  }.merge(cfg)
  ap config
  # データの初期化
  @chunk_size = config[:chunk_size] # 学習データサイズ
  @midnight_ratio = 0.8
  @midnight_strategy = config[:midnight_strategy]
  @max_strage = config[:max_strage]
  @battery = 2000.0
  @address = config[:address]
  @weather = -1 # none 
  @filter = filter_init config[:filter]
  @target = config[:target]
  @solars = config[:solars]
  @demands = config[:demands]
  @clock = 0
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
   }
  }
  @buy_times = Array.new((1440/TIMESTEP),0.0) # 夜間に決定した間別の購入量配列
  @may_get_solar = 0.0 # 次の日に得られる発電量
 end

 # 需要量のセット
 def set_demands datas
  @demands.clear
  @demands = datas
 end

 # 太陽光発電量をセット
 def set_solars datas
  @solars=[]
  @solars = datas.map{|x| x/2.0 } # 発電効率50%
  
 end

 # 一日の行動をする
 def date_action
  timeline = ""
  results = [] # 買った電力量
  bs = [] # 蓄電池の状況
  predicts = [0.0] # 予測値(実験用)
  reals = []
  sells = [] # simdatas のsellsのポインター
  buys = []
  simdatas = {buy: results, battery: bs, predict: predicts, real: reals, sell: sells} # 結果
  for cnt in 0..(1440/TIMESTEP-1) do
   if @filter.nil? # Filter使わないとき
    if cnt > 4*(60/TIMESTEP)  && cnt < 23*(60/TIMESTEP) # タイムステップ（最初の1時間と最後の1時間を除く）
     crnt_solar = @solars[cnt]
     crnt_demand = @demands[cnt]

     power_value = buy_power_2(crnt_demand,crnt_solar) # 予測考慮なし
     #sell_value = sell_power # 余剰電力を売る

     results << power_value
     #sells << sell_value
     @sells = 0.0 if @battery > @target && cnt < 9*(60/TIMESTEP) && @midnight_strategy
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
      @battery += @buy_times[cnt] # Battery更新
      sells << 0.0
      ### 描画部分
      timeline = @buy_times[cnt] != 0 ? timeline + " o" : timeline + " _"
      print "\e[33m購入状況:#{timeline}\e[0m\r"
     else # 夜間戦略なし
      crnt_solar = @solars[cnt]
      predicts << crnt_solar
      reals << crnt_solar
      if @battery < @target # バッテリー容量が目標値を下回るとき
       results << @target - @battery # 目標値になるように電力を買う
       sells << 0.0
       @battery = @target
      else
       results << 0.0
       sells << sell_power 
      end
      timeline = @battery < @target != 0 ? timeline + " o" : timeline + " _"
      print "\e[33m購入状況:#{timeline}\e[0m\r"
     end
    end
   elsif @filter.eql?("normal") # 平均した曲線モデルで予測する場合
    if cnt > 4*(60/TIMESTEP)  && cnt < 23*(60/TIMESTEP) # タイムステップ（最初の1時間と最後の1時間を除く）
     crnt_solar = @solars[cnt]
     #next_solar = @weather_models[@weather][cnt+1]
     next_solar = @filter.ave_models[@weather][cnt+1]
     #next_solar = @weather_model[cnt+1]
     crnt_demand = @demands[cnt]
     next_demand = @demands[cnt+1]

     #power_value = buy_power(crnt_demand,next_demand,crnt_solar,next_solar) # 予測考慮する
     power_value = buy_power_2step(crnt_demand,next_demand,crnt_solar,next_solar,cnt) # 予測考慮する
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
    if cnt > 4*(60/TIMESTEP)  && cnt < 23*(60/TIMESTEP) # タイムステップ（最初の1時間と最後の1時間を除く）
     crnt_solar = @solars[cnt]
     #next_solar = @filter.next_value_predict(crnt_solar, cnt)
     next_solar = @filter.predict_next_value(crnt_solar, cnt)
     @filter.train_per_step crnt_solar
     crnt_demand = @demands[cnt]
     next_demand = @demands[cnt+1]
     #power_value = buy_power(crnt_demand,next_demand,crnt_solar,next_solar) # 予測考慮する（通常版）
     power_value = buy_power_2step(crnt_demand,next_demand,crnt_solar,next_solar,cnt) # 予測考慮する
     #power_value = buy_power_3(crnt_demand,next_demand,crnt_solar,next_solar) # 予測考慮する
     #sell_value = sell_power # 余剰電力を売る

     results << power_value
     #sells << sell_value
     #### 朝のうちに買っておいた蓄電量をあまり売らない（買ってから蓄電池目標量を下回った時だけ）
     @sells = 0.0 if @battery > @target && cnt < 9*(60/TIMESTEP) && @midnight_strategy
     sells << @sells 
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
     print "\e[33m購入状況:#{timeline}\e[0m\r"

    else # 夜中と早朝の戦略
     @filter.train_per_step @solars[cnt] # 学習はする（つじつま合わせ）
     if @midnight_strategy # 夜間の戦略有り
      reals << @solars[cnt]
      predicts << @solars[cnt]
      results << @buy_times[cnt] # 予め買う予定の電力量の購入
      @battery += @buy_times[cnt] # Battery更新
      sells << 0.0
      ### 描画部分
      timeline = @buy_times[cnt] != 0 ? timeline + " o" : timeline + " _"
      print "\e[33m購入状況:#{timeline}\e[0m\r"
     else # 夜間戦略なし
      next_solar = @filter.predict_next_value(@solars[cnt], cnt)
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
      ### 描画部分
      if @battery < @target
       timeline += " o"
      elsif @sells > 0.0
       timeline += " x"
      else
       timeline += " _"
      end
      print "\e[33m購入状況:#{timeline}\e[0m\r"
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

 # 買う量を決定（価格と量を返り値とする）
 # 引数
 #  d0: 現在の需要量
 #  d1: 次のの需要量 
 #  s0: 現在の太陽光発電量
 #  s1: 予測の太陽光発電量
 # 戦略は需要量から発電量を引いた値の正負で変わることに注意
 # 内部プログラムのt0,t1は絶対値であり，各ケース内の場合分け
 # で用いられる.
 def buy_power d0, d1, s0, s1
  max_buy = 500.0
  t0 = (d0 - s0).abs
  t1 = (d1 - s1).abs
  value = 0.0 # 買電量の初期化
  #print "solar:#{s0}, demand:#{d0}\n"
  if (d0 - s0) > 0 && (d1 - s1) > 0 # Case 1 ------------------
   if @battery - (t0  + t1) < 0 # 予測と現在の需要和が現時点の蓄電量を超えるとき（空になる）
    value = @battery + t1 > @max_strage ? @max_strage - @battery : t0 + t1
   elsif @battery - (t0 + t1) > 0 && @battery - (t0 + t1) < @target # 未来予測後も目標値以下のとき
    value = @battery + t1 <= @max_strage ? t0 + t1 : @max_strage - @battery
    #p t1
    #p value
   elsif @battery - (t1 + t0) <= @max_strage # それ以外は買わない
    # 買わない
    #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0 
    sell_power_2
   end
  elsif d0 - s0 > 0 && d1 - s1 <= 0 # Case 2 -------------------
   if @battery - (t0 - t1) > 0 && @battery - (t0 - t1) <= @target
    value = t0 - t1
    #p value
   elsif @battery - (t0 - t1) > @target
    if @battery - t0 < 0
     value =  t0 + @target - @battery
     #p value
    elsif @battery - t0 > 0
     # 買わない
     #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
     sell_power_2
    end
   end
   # Exception
   return 0.0
  elsif d0 - s0 <= 0 && d1 - s1 > 0 # Case 3 -------------------
   if @battery + t0 - t1 >= @target
    # 買わない
    #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
   elsif @battery + t0 - t1 < @target
    if @battery + t0 > @max_strage
     # 買わない
     #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
     sell_power_2
    elsif @battery + t0 <= @max_strage
     #value = @max_strage - (@battery + t1)
     value = t1 - t0
     #p value
    end
   end
  elsif d0 - s0 <= 0 && d1 - s1 <= 0 # Case 4 -------------------
   if @battery + t0 + t1 < @target
    value = @target - (@battery + (t0 + t1))
   else
    #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
    sell_power_2
   end
  end
  value = max_buy > value ? value : max_buy
  @battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0 
  @battery = @battery - d0 + value
  return value 
 end

 # ２つ先がどうなるかも考慮に入れる
 # 買いが乱高下しないようにするための戦略
 # 現在時刻:time
 def buy_power_2step d0, d1, s0, s1, time
  max_buy = 500.0
  t0 = (d0 - s0).abs
  t1 = (d1 - s1).abs
  # 二期先のデータを定義する
  d2 = @demands[time+2]
  s2 = @filter.ave_models[@weather][time+2]
  #s2 = @weather_models[@weather][time+2]
  t2 = (d2 - s2).abs
 
  value = 0.0 # 買電量の初期化
  #print "solar:#{s0}, demand:#{d0}\n"
  if (d0 - s0) > 0 && (d1 - s1) > 0 # Case 1 ------------------
   if @battery - (t0  + t1) < 0 # 予測と現在の需要和が現時点の蓄電量を超えるとき（空になる）
    value = @battery + t1 > @max_strage ? @max_strage - @battery : t0 + t1
    if d2 - s2 > 0
     value = (value + t2)*0.7/2.0 
    else
     value = value - t2 < 0.0 ? 0.0 : value - t2
    end
   elsif @battery - (t0 + t1) > 0 && @battery - (t0 + t1) < @target # 未来予測後も目標値以下のとき
    value = @battery + t1 <= @max_strage ? t0 + t1 : @max_strage - @battery
    if d2 - s2 > 0
     value = (value + t2)*0.7/2.0
    else
     value = value - t2 < 0.0 ? 0.0 : value - t2
    end
    #p t1
    #p value
   elsif @battery - (t1 + t0) <= @max_strage # それ以外は買わない
    # 買わない
    #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
    if (d2 - s2) > 0
     value = t2 if @battery - (t1 + t0) - t2 < @target
    end
    sell_power_2
   end
  elsif d0 - s0 > 0 && d1 - s1 <= 0 # Case 2 -------------------
   if @battery - (t0 - t1) > 0 && @battery - (t0 - t1) <= @target
    value = t0 - t1
    if d2 - s2 > 0
     value = (value + t2)*0.7/2.0 
    else
     value = value - t2 < 0.0 ? 0.0 : value - t2
    end
    #p value
   elsif @battery - (t0 - t1) > @target
    if @battery - t0 < 0
     value =  t0 + @target - @battery
     if d2 - s2 > 0
      value = (value + t2)*0.7/2.0
     else
      value = value - t2 < 0.0 ? 0.0 : value - t2
     end
     #p value
    elsif @battery - t0 > 0
     # 買わない
     #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
     if d2 - s2 > 0
      value = t2 if @battery - t0 - t2 < @target
     end
     sell_power_2
    end
   end
   # Exception
   return 0.0
  elsif d0 - s0 <= 0 && d1 - s1 > 0 # Case 3 -------------------
   if @battery + t0 - t1 >= @target
    # 買わない
    #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
    if d2 - s2 > 0
     value = t2 if @battery + t0 -t1 - t2 < @target
    end
    sell_power_2
   elsif @battery + t0 - t1 < @target
    if @battery + t0 > @max_strage
     # 買わない
     #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
     if d2 - s2 > 0
      value = t2 if @battery + t0 - t2 < @target
     end
     sell_power_2
    elsif @battery + t0 <= @max_strage
     #value = @max_strage - (@battery + t1)
     value = t1 - t0
     if d2 - s2 > 0
      value = (value + t2)*0.7/2.0 
     else
      value = value - t2 < 0.0 ? 0.0 : value - t2
     end
     #p value
    end
   end
  elsif d0 - s0 <= 0 && d1 - s1 <= 0 # Case 4 -------------------
   if @battery + t0 + t1 < @target
    value = @target - (@battery + (t0 + t1))
    if d2 - s2 > 0 ## 2013-07-31変更
     value = (value + t2)*0.7/2.0 
    else
     value = value - t2 < 0.0 ? 0.0 : value - t2
    end
   else
    #@battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0
    if d2 - s2 > 0
     value = t2 if @battery + t0 + t1 - t2 < @target
    end
    sell_power_2
   end
  end
  value = max_buy > value ? value : max_buy
  @battery = @battery + s0 - d0 + value > @max_strage ? @max_strage : @battery + s0 - d0 + value
  #@battery = @battery - d0 + value
  return value  
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
  over_condition = @battery - @target < 500.0
  result = 0.0
  if over_condition
    return result
  else
   result = @battery - @target - 500.0 > 500.0 ? 500.0 : @battery - @target - 500.0
   @battery = @battery - result
   return result 
  end
 end

 # 電力を売る
 def sell_power 
  over_condition = @battery - @target < 500.0
  result = 0.0
  if over_condition
    return result
  else
   result = @battery - @target - 500.0 > 500.0 ? 500.0 : @battery - @target - 500.0
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
  @clock += 1
 end

 # 1日の初期化
 def init_date
  @clock = 0
  @filter.particles_zero unless @filter.nil?
  train_data_per_day
  #@filter.init_data if !@filter.nil? && !@filter.eql?("normal")
 end

 ## 夜間にチェックする
 def select_time_and_value_to_buy
  cnt = 0
  chunk = 0
  trains = @trains[:demands][@weather]
  sum_demand = 0.0
  while trains.size > cnt 
   sum_demand += @trains[:demands][@weather][cnt]
   cnt += 1
   if cnt % (1440/TIMESTEP) == 0 && cnt / (1440/TIMESTEP) != 0
    chunk += 1
   end
  end

  sum_demand /= chunk ## 次の日の電力需要
  per_demand = -> (value){ (value/(4.0*(60/TIMESTEP)))} # ４時間分割する方程式

  sum_solar = @trains[:solars][@weather].inject(0.0){|acc, x| acc+=x}
  sum_demand = @demands.inject(0.0){|acc,x| acc+=x}
  ##################################################################
  ## 夜間の電力購入の戦略
  ##
  ##@may_get_solar = sum_solar / (@trains[:solars][@weather].size / (1440/TIMESTEP))
  one = 0.0
  if sum_solar - sum_demand > 0.0 && trains.size > 0 && @trains[:solars][@weather].size > 0# 次の日の発電量と需要の差が
   # 買わない
  else ## 発電量が下回るとき（主に雨とか曇りに起きやすい）
   if @battery + (sum_demand - sum_solar ) < @max_strage * @midnight_ratio # 最大容量を超えないとき
    tmp_buy = (sum_demand - sum_solar)
    one = per_demand.call tmp_buy # ４時間分割
   else # 最大容量を超えるとき 
    tmp_buy =  @max_strage * @midnight_ratio - @battery
    one = per_demand.call tmp_buy # 四時間分割
   end
  end
  print "\t \e[32m今日の夜間の購入量情報：\n"
  print "\t >> 予測需要量：#{sum_demand}\n\t >> 予測発電量：#{sum_solar}\n\t >> ワンステップごとの購入量：#{one}\n\e[0m" 
  
  # 買う時間を決定
  for i in 0..(4*((60/TIMESTEP))-1)
   @buy_times[i] = one
  end  

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
  select_time_and_value_to_buy # 夜間におよその購入量と蓄電量を概算する 
 end

 private

 #####
 # 一日ごとに学習していく
 #
 def train_data_per_day
  @trains[:demands][@weather].concat @demands.clone
  @trains[:solars][@weather].concat @solars.clone
  if @chunk_size * (1440/TIMESTEP) < @trains[:demands][@weather].size
   @trains[:demands][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1)
   @trains[:solars][@weather].slice!(0..@chunk_size*(1440/TIMESTEP)-1)
  end
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

end
