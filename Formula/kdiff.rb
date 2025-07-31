class Kdiff < Formula
    desc "Kubernetes diff tool for comparing deployments and configurations"
    homepage "https://github.com/bucketplace/sre"
    url "https://github.com/bucketplace/sre/archive/v0.0.1.tar.gz"
    sha256 "0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5"
    
    def install
      cd "utils/kdiff" do
      
        system "echo '#!/bin/bash' > kdiff_standalone"
        system "echo '' >> kdiff_standalone"
        
      
        Dir["lib/*.sh"].each do |lib_file|
          system "echo '# === #{File.basename(lib_file)} ===' >> kdiff_standalone"
          system "cat #{lib_file} >> kdiff_standalone"
          system "echo '' >> kdiff_standalone"
        end

        system "tail -n +2 kdiff.sh | grep -v 'source.*lib/' >> kdiff_standalone"
        
      
        system "chmod", "+x", "kdiff_standalone"
        bin.install "kdiff_standalone" => "kdiff"
      end
    end
    
    test do
      system "#{bin}/kdiff", "--help"
    end
  end