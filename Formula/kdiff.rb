class Kdiff < Formula
  desc "Kubernetes diff tool for comparing deployments and configurations"
  homepage "https://github.com/bucketplace/sre"
  url "file:///dev/null"
  version "0.0.1"
  
  def install
    github_token = ENV["GITHUB_TOKEN"]
    
    if github_token.nil? || github_token.empty?
      begin
        github_token = `gh auth token`.strip
        if $?.exitstatus != 0 || github_token.empty?
          github_token = nil
        end
      rescue
        github_token = nil
      end
    end
    
    if github_token.nil? || github_token.empty?
      begin
        gh_config = `gh auth status 2>&1`
        if gh_config.include?("Logged in to github.com")
          github_token = "use_gh_cli"
        end
      rescue
      end
    end
    
    if github_token.nil? || github_token.empty?
      odie <<~EOS
        GitHub token required for private repository access.
        
        Please try one of these methods:
        1. Set environment variable: export GITHUB_TOKEN=your_token
        2. Login with gh CLI: gh auth login
        3. Create personal access token at: https://github.com/settings/tokens
      EOS
    end
    
    if github_token == "use_gh_cli"
      system "gh", "api", "/repos/bucketplace/sre/tarball/v#{version}", 
             "--jq", ".", "> sre.tar.gz"
    else
      system "curl", "-L", "-H", "Authorization: token #{github_token}",
             "https://api.github.com/repos/bucketplace/sre/tarball/v#{version}",
             "-o", "sre.tar.gz"
    end
    
    unless File.exist?("sre.tar.gz") && File.size("sre.tar.gz") > 0
      odie "Failed to download repository. Check your GitHub access permissions."
    end
    
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
  
  test do
    system "#{bin}/kdiff", "--help"
  end
end