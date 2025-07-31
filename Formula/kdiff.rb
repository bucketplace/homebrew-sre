class Kdiff < Formula
  desc "Kubernetes diff tool for comparing deployments and configurations"
  homepage "https://github.com/bucketplace/sre"
  version "0.0.1"
  
  def install
    
    github_token = ENV["GITHUB_TOKEN"] || `gh auth token 2>/dev/null`.strip
    
    if github_token.empty?
      odie "GitHub token required. Run 'gh auth login' or set GITHUB_TOKEN environment variable"
    end
    
    
    system "curl", "-L", "-H", "Authorization: token #{github_token}",
           "https://api.github.com/repos/bucketplace/sre/tarball/v#{version}",
           "-o", "sre.tar.gz"
    
    
    system "tar", "-xzf", "sre.tar.gz", "--strip-components=1"
    
    
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
  
  def caveats
    <<~EOS
      This formula requires GitHub authentication.
      Make sure you're logged in with: gh auth login
      Or set GITHUB_TOKEN environment variable.
    EOS
  end
  
  test do
    system "#{bin}/kdiff", "--help"
  end
end