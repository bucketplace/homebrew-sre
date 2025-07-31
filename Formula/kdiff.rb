class Kdiff < Formula
  desc "Kubernetes diff tool for comparing deployments and configurations"
  homepage "https://github.com/bucketplace/homebrew-sre"
  url "https://github.com/bucketplace/homebrew-sre/archive/refs/tags/v0.0.1.tar.gz"
  
  def install
    cd "utils/kdiff" do
      system "echo '#!/bin/bash' > kdiff_standalone"
      system "echo '' >> kdiff_standalone"
      
      Dir["lib/*.sh"].sort.each do |lib_file|
        system "echo '# === #{File.basename(lib_file)} ===' >> kdiff_standalone"
        system "cat #{lib_file} >> kdiff_standalone"
        system "echo '' >> kdiff_standalone"
      end
      
      system "echo '# === Main Script ===' >> kdiff_standalone"
      system "tail -n +2 kdiff.sh | grep -v 'source.*lib/' >> kdiff_standalone"
      
      system "chmod", "+x", "kdiff_standalone"
      bin.install "kdiff_standalone" => "kdiff"
    end
  end
  
  test do
    system "#{bin}/kdiff", "--help"
  end
end