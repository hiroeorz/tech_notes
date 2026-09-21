# typed: false

# Tapioca が生成する gem RBI は、実行環境の Bundler の実装に依存して
# `Bundler::ConnectionPool::ForkTracker` を参照することがある（Bundler 4.0.12 以降が
# vendored connection_pool で `ForkTracker` を定義し、ffi の RBI に Process への extend として現れる）。
# Bundler は default gem のため RBI が生成されず、環境によって srb tc が
# 「Unable to resolve constant `Bundler::ConnectionPool`」で失敗する。
# 参照先の内部定数だけをここで補い、生成 RBI の揺れを吸収する。
class Bundler::ConnectionPool
  module ForkTracker
  end
end
