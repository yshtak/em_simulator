require "#{File.expand_path File.dirname __FILE__}/../filter/02_particle_filter"

class HomeAgent
 attr_accessor :strage, :target, :filter
 SIM_INTERVAL = 24 * 4 # 15分刻み

 def initialize cfg={}
  config = {
   filter: 'none', # 未来予測のためのフィルターのタイプ
   max_strage: 4000.0, # 蓄電容量(Wh)
   target: 2000.0, # 目標蓄電量(Wh)
   solars: [], # 15分毎の1日の電力発電データ
   demands: [], # 15分毎の1日の需要データ
   address: "unknown"
  }.merge(cfg)
  ap config
  # データの初期化
  @max_strage = config[:max_strage]
  @battery = 2000.0
  @address = config[:address]
  @weather = "none"
  @weather_model = []
  @weather_models = {'sunny' => [], 'rainny' => [], 'cloudy' => []}
  @filter = filter_init config[:filter]
  @target = config[:target]
  @solars = config[:solars]
  @demands = config[:demands]
  @clock = 0
  @sells = (0..SIM_INTERVAL-1).map{|i| 0.0}
 end

 # 需要量のセット
 def set_demands datas
  @demands.clear
  @demands = datas
 end

 # 太陽光発電量をセット
 def set_solars datas
  @solars.clear
  @solars = datas
 end

 # 天候モデルの初期化
 def init_weather_models
  root = File.expand_path File.dirname __FILE__
  @weather_models['sunny'] = open("#{root}/../data/solar/#{@address}/models/sunny.csv").read.split(',').map{|x|x.to_f}
  @weather_models['cloudy'] = open("#{root}/../data/solar/#{@address}/models/cloudy.csv").read.split(',').map{|x|x.to_f}
  @weather_models['rainny'] = open("#{root}/../data/solar/#{@address}/models/rainny.csv").read.split(',').map{|x|x.to_f} 
 end

 # TODO: 例外処理の追加
 def select_weather type
  root = File.expand_path File.dirname __FILE__
  tmp_model = (0..SIM_INTERVAL-1).map{|x| 0.0}
  case type
  when "sunny"
   #@weather_model = open("#{root}/../data/solar/#{@address}/models/#{type}.csv").read.split(',').map{|x|x.to_f}
   tmp_model = @weather_models[type].clone
  when "rainny"
   #@weather_model = open("#{root}/../data/solar/#{@address}/models/#{type}.csv").read.split(',').map{|x|x.to_f}
   tmp_model = @weather_models[type].clone
  when "cloudy"
   #@weather_model = open("#{root}/../data/solar/#{@address}/models/#{type}.csv").read.split(',').map{|x|x.to_f}
   tmp_model = @weather_models[type].clone
  end
  if @filter.eql?("normal")
   @weather = type
  else
   @filter.set_weather type if !@filter.nil?
   @filter.set_model_data tmp_model if !@filter.nil?
  end
 end

 # 一日の行動をする
 def date_action
  results = [] # 買った電力量
  bs = [] # 蓄電池の状況
  predicts = [0.0] # 予測値(実験用)
  reals = []
  sells = [] # simdatas のsellsのポインター
  simdatas = {buy: results, battery: bs, predict: predicts, real: reals, sell: sells} # 結果
  for cnt in 0..SIM_INTERVAL-1 do
   bs << @battery
   if @filter.nil? # Filter使わないとき
    if cnt >(4*1) && cnt < (23*4) # タイムステップ（最初の1時間と最後の1時間を除く）
     crnt_solar = @solars[cnt]
     crnt_demand = @demands[cnt]

     power_value = buy_power_2(crnt_demand,crnt_solar) # 予測考慮なし
     sell_value = sell_power # 余剰電力を売る

     results << power_value
     sells << sell_value
     predicts << crnt_solar
     reals << crnt_solar
    else # 最初の1時間と最後の一時間
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
    end
   elsif @filter.eql?("normal") # 平均した曲線モデルで予測する場合
    if cnt > (4*1) && cnt < (23 * 4)
     crnt_solar = @solars[cnt]
     next_solar = @weather_models[@weather][cnt+1]
     crnt_demand = @demands[cnt]
     next_demand = @demands[cnt+1]

     #power_value = buy_power(crnt_demand,next_demand,crnt_solar,next_solar) # 予測考慮する
     power_value = buy_power_3(crnt_demand,next_demand,crnt_solar,next_solar) # 予測考慮する
     sell_value = sell_power # 余剰電力を売る

     results << power_value
     sells << sell_value
     predicts << next_solar
     reals << crnt_solar
    else
     next_solar = @weather_models[@weather][cnt]
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
    if cnt > (4 * 1) && cnt < (23 * 4) # 日中（朝から夜まで）の戦略
     crnt_solar = @solars[cnt]
     next_solar = @filter.next_value_predict(crnt_solar, cnt)
     crnt_demand = @demands[cnt]
     next_demand = @demands[cnt+1]

     #power_value = buy_power(crnt_demand,next_demand,crnt_solar,next_solar) # 予測考慮する
     power_value = buy_power_3(crnt_demand,next_demand,crnt_solar,next_solar) # 予測考慮する
     sell_value = sell_power # 余剰電力を売る

     results << power_value
     sells << sell_value
     predicts << next_solar
     reals << crnt_solar
    else # 夜中と早朝の戦略
     #ap cnt
     next_solar = @filter.next_value_predict(@solars[cnt], cnt)
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
   end
  end
  #p predicts[45]
  #p reals[45]
  #return [results, bs]
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
   end
  end
  @battery = @battery + s0 > @max_strage - d0 ? @max_strage - d0  : @battery + s0 
  @battery = @battery - d0 + value
  return value 
 end

 # 現在時刻のみ見る場合の戦略
 def buy_power_2 d0, s0
  if d0 > s0
   if @battery - (d0 - s0) > @target
    @battery = @battery - (d0 - s0)
    return 0.0
   else
    value =  @target - (@battery - (d0 - s0))
    @battery = @battery - d0 + value
    return value
   end
  else
   @battery =  @battery + (s0 - d0) < @max_strage ? @battery + (s0 - d0) : @max_strage
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
    next_battery = crnt_condition + result # 次の時刻でのバッテリー残量予測
    # 買った分で最大容量を超えてしまったときは超えないようにする
    result = next_battery > @max_strage ? result - (next_battery - @max_strage) : result
   else # 次の時刻では目標値が達成できるとき
    # 買わない 売るかどうかは保留したほうがいい？ただし0にはしないようにする
    result = 1.0 if crnt_condition == 0.0
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
   end
  end
  @battery = crnt_condition + result # バッテリー残量の状態遷移
  return result
 end

 # 買う相手先の選択
 def select_target id
  
 end

 # 電力を売る
 def sell_power 
  if @battery <= (@target)
   return 0.0
  end
  over_condition = @battery - @target > 500.0
  result = 0.0
  if over_condition
   result = 500.0
  else
   result = @battery - @target
  end
  @battery = @battery - result
  return result
 end

 # 時間をすすめる
 def next_time time
  @clock += 1
 end

 # 1日の初期化
 def init_date
  @clock = 0
  @filter.init_data if !@filter.nil? && !@filter.eql?("normal")
 end

 private
 # フィルターの初期化
 def filter_init type
  case type
  when 'pf'
   init_weather_models
   return @filter = ParticleFilter.new 
  when 'normal'
   init_weather_models
   return @filter = 'normal'
  when 'none'
   return nil
  end
  return nil
 end

end
