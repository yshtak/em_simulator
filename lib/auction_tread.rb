require 'redis'
require 'hiredis'
require 'oj'
require 'time'
##############################
# RedisServerに保存されているオークションの価格を取ってくる
# オークションに必要な情報
# Timestamps: いつのオークションデータか
# タイムステップごとの価格
# タイムステップごとの買い手の人数
# タイムステップごとの
# 
##
class AuctionThread
 def initialize cfg={}
  @config = {
   id: 'comm1',
   weather: 'none',
   timestep: 96
  }.merge(cfg)
  @redis = Redis.new driver: 'hiredis'
  @market_data = {price: 100.0 , buyers_count: 0}
  @timestamp = publish_timestamp
  @weather = @config[:weather]
 end

 # 天気を設定する
 def set_weather weather
  @weather = weather
 end

 # 一週間の結果を取得 
 def get_weekly_threads type
  size = @redis.llen(type)
  ids = @redis.lrange(type, 0, size)
  return ids.map{|id| @redis.lrange(id,0,size-1).map{|data| Oj.load data}}
 end 

 # 価格の更新
 def update_price price
  @market_data[:price] = price
 end

 # 買った人がいた時
 def inc_buyer
  @market_data[:buyers_count] += 1
 end 

 # Timestampを取得
 def publish_timestamp
  Time.now.strftime("%Y%m%d") 
 end

 # オークションの終了
 def done_auction
  @redis.lpop @weather if @redis.llen(@weather) == 7
  @redis.rpush @weather, @timestamp
  @timestamp = (Time.parse(@timestamp) + 86400.0).strftime("%Y%m%d")
 end

 # 一日を更新する
 def init_date weather
  set_weather weather
  @market_data = {price: 100.0, buyers_count: 0} # 学習したものを利用
 end
 
 # DBを削除
 def destroy
  destroy_thread
 end

 def get_thread
  @redis.lrange(@timestamp, 0, @redis.llen(@timestamp)).map{|data| Oj.load data}
 end

 def next_step
  @redis.rpush @timestamp, Oj.dump(@market_data)
  @market_data = {price: 100.0 , buyers_count: 0}
 end

 private
 def destroy_thread
  @redis.flushdb 
 end

 def dump_thread

 end

end
