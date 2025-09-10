class R53 < Formula
  desc "AWS Route 53 Management Tool"
  homepage "https://github.com/bucketplace/homebrew-sre"
  url "https://github.com/bucketplace/homebrew-sre/archive/refs/tags/v0.0.10.tar.gz"
  
  def install
    cd "utils/r53" do
      system "echo '#!/bin/bash' > r53_standalone"
      system "echo '' >> r53_standalone"

      Dir["lib/*.sh"].sort.each do |lib_file|
        system "echo '# === #{File.basename(lib_file)} ===' >> r53_standalone"
        system "cat #{lib_file} >> r53_standalone"
        system "echo '' >> r53_standalone"
      end

      system "echo '# === Main Script ===' >> r53_standalone"
      system "tail -n +2 r53.sh | grep -v 'source.*lib/' >> r53_standalone"
      system "chmod", "+x", "r53_standalone"
      bin.install "r53_standalone" => "r53"
    end
  end
end