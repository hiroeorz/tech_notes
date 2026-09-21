# typed: false

# ruby-vips は FFI 経由で実行時にクラスを定義するため、Tapioca が生成する
# gem RBI には `Vips::Image` が含まれない。一方 image_processing 2.x の生成
# RBI は `Vips::Image` を参照するため、そのままでは srb tc が
# 「Unable to resolve constant `Image`」で失敗する。
# 参照解決に必要な最小限のクラス定義だけをここで補い、生成 RBI の揺れを吸収する。
# 実行時の挙動には影響しない。
module Vips
  class Image
  end
end
