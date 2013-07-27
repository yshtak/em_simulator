##
# Particle FilterのParitlceクラス
##
module Particle
 ## ガウス分布関数
 def gaussian x, mu, sigma
  return Math.exp(-(x-mu)/2*sigma)/Math.sqrt(2 * Math::PI * sigma)
 end

 class Particle
  attr_accessor :value, :weight
  #== コンストラクタ
  # x: 値
  # w: 重み（尤度）
  def initialize x=0.0,w=1.0
   @value = x
   @weight = w
  end

  # 重みをかけた値を返す
  def weigth_value
   return x*w
  end

  def to_s
   return "value:#{x}\tweight:#{w}"
  end

 end

 # Box=Muller法による正規乱数生成し確率を返す
 class RandomBoxMuller
  def initialize config={}
   @config = {
    mean: 0,
    sigma: 1.0,
    rand_number: 10
   }.merge(config)
   @mean = @config[:mean]
   @sigma = @config[:sigma]
   @rand_number = @config[:rand_number]
  end
  
  def generate_rand
   results = []
   # N回乱数生成を繰り返す
   0.upto(@rand_number - 1) do |num|
    results << rnd_v( @mean, @sigma)
   end
   return results
  end

  # パラメータを随時設定可能の奴
  # 確率密度を取得
  def generate_rand_norm mean, sigma, rand_number
   results = []
   # N回乱数生成を繰り返す
   0.upto(rand_number - 1) do |num|
    results << rnd_p(mean, sigma)
   end
   return results
  end
  
  # 正規乱数を取得
  def generate_rand_normval mean, sigma, rand_number
   results = []
   # N回乱数生成を繰り返す
   0.upto(rand_number - 1) do |num|
    results << rnd_v(mean, sigma)
   end
   return results
  end

  # 正規分布の確率をランダムで取得  
  def rnd_p mean, sigma
   r_1 = rand
   r_2 = rand
   x = Math.sqrt(sigma) * Math.sqrt(-2.0 * Math.log(r_1)) * Math.cos(2.0 * Math::PI * r_2) + mean
   #y = Math.sqrt(-2.0 * Math.log(r_1)) * Math.sin(2.0 * Math::PI * r_2) + @mean
   return gaussian x
  end

  # 正規分布の確率変数をランダムで取得
  def rnd_v mean, sigma 
   r_1 = rand
   r_2 = rand
   x = Math.sqrt(sigma) * Math.sqrt(-2.0 * Math.log(r_1)) * Math.cos(2.0 * Math::PI * r_2) + mean
   #y = Math.sqrt(-2.0 * Math.log(r_1)) * Math.sin(2.0 * Math::PI * r_2) + @mean
   return x
  end

  def gaussian x
   return Math.exp(-(x - @mean)**2/2.0*@sigma) / Math.sqrt(2.0*Math::PI*@sigma)
  end
 end

end
