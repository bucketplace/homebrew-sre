class Kdiff < Formula
  desc "Kubernetes diff tool for comparing deployments and configurations"
  homepage "https://github.com/bucketplace/sre"
  url "file:///dev/null"
  version "0.0.1"
  
  def install
    github_token = find_github_token
    
    if github_token.nil? || github_token.empty?
      odie <<~EOS
        GitHub authentication required for private repository access.
        
        Please authenticate using one of these methods:
        1. gh auth login
        2. git config --global github.token YOUR_TOKEN  
        3. export GITHUB_TOKEN=YOUR_TOKEN
        
        Create token at: https://github.com/settings/tokens (with 'repo' scope)
      EOS
    end
    
    ENV["HOMEBREW_GITHUB_API_TOKEN"] = github_token
    
    puts "🔍 Downloading from private repository using auto-detected token..."
    
    download_and_extract_repo(github_token)
    
    puts "✅ Building kdiff..."
    build_kdiff
    puts "🎉 kdiff installed successfully!"
  end
  
  private
  
  def find_github_token
    token = ENV["GITHUB_TOKEN"] || ENV["HOMEBREW_GITHUB_API_TOKEN"]
    return token unless token.nil? || token.empty?
    
    begin
      token = `gh auth token 2>/dev/null`.strip
      return token if $?.exitstatus == 0 && !token.empty?
    rescue
    end
    
    gh_config_path = File.expand_path("~/.config/gh/hosts.yml")
    if File.exist?(gh_config_path)
      begin
        require 'yaml'
        gh_config = YAML.load_file(gh_config_path)
        token = gh_config.dig("github.com", "oauth_token")
        return token unless token.nil? || token.empty?
      rescue
      end
    end
    
    begin
      token = `git config --get github.token 2>/dev/null`.strip
      return token unless token.empty?
    rescue
    end
    
    begin
      cred_output = `printf "protocol=https\nhost=github.com\n\n" | git credential fill 2>/dev/null`
      if match = cred_output.match(/password=(.+)/)
        token = match[1].strip
        return token unless token.empty?
      end
    rescue
    end
    
    nil
  end
  
  def download_and_extract_repo(token)
    if system("which gh > /dev/null 2>&1")
      success = system("gh", "api", "/repos/bucketplace/sre/tarball/v#{version}",
                      "--jq", ".", "-o", "sre.tar.gz")
      
      if success && File.exist?("sre.tar.gz") && File.size("sre.tar.gz") > 0
        system "tar", "-xzf", "sre.tar.gz", "--strip-components=1"
        return
      end
    end
    
    success = system("curl", "-L", "-H", "Authorization: token #{token}",
                    "https://api.github.com/repos/bucketplace/sre/tarball/v#{version}",
                    "-o", "sre.tar.gz", "-f", "-s")
    
    unless success && File.exist?("sre.tar.gz") && File.size("sre.tar.gz") > 0
      odie "❌ Failed to download repository. Check your GitHub access permissions."
    end
    
    system "tar", "-xzf", "sre.tar.gz", "--strip-components=1"
  end
  
  def build_kdiff
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