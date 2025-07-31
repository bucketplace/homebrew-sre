class Kdiff < Formula
  desc "Kubernetes diff tool for comparing deployments and configurations"
  homepage "https://github.com/bucketplace/sre"
  url "file:///dev/null"
  version "0.0.1"
  
  def install
    puts "🔍 Downloading via GitHub CLI..."
    
    success = system("gh", "api", "/repos/bucketplace/sre/tarball/v#{version}",
                     "-H", "Accept: application/vnd.github+json",
                     "--jq", ".",
                     "-o", "sre.tar.gz")
    
    unless success && File.exist?("sre.tar.gz") && File.size("sre.tar.gz") > 0
      puts "🔄 Trying alternative download methods..."
      
      github_token = ENV["GITHUB_TOKEN"] || ENV["HOMEBREW_GITHUB_API_TOKEN"]
      
      if github_token && !github_token.empty?
        puts "  • Using environment token..."
        success = system("curl", "-L", 
                         "-H", "Authorization: token #{github_token}",
                         "-H", "Accept: application/vnd.github+json",
                         "https://api.github.com/repos/bucketplace/sre/tarball/v#{version}",
                         "-o", "sre.tar.gz",
                         "--fail", "--silent")
      end
      
      unless success && File.exist?("sre.tar.gz") && File.size("sre.tar.gz") > 0
        puts "  • Trying git clone with SSH..."
        if system("git", "clone", "--depth", "1", "--branch", "v#{version}",
                  "git@github.com:bucketplace/sre.git", "temp-repo", 
                  [:out, :err] => "/dev/null")
          
          system("tar", "-czf", "sre.tar.gz", "-C", "temp-repo", ".")
          system("rm", "-rf", "temp-repo")
          success = File.exist?("sre.tar.gz") && File.size("sre.tar.gz") > 0
        end
      end
      
      unless success && File.exist?("sre.tar.gz") && File.size("sre.tar.gz") > 0
        puts "  • Trying git clone with HTTPS..."
        if system("git", "clone", "--depth", "1", "--branch", "v#{version}",
                  "https://github.com/bucketplace/sre.git", "temp-repo",
                  [:out, :err] => "/dev/null")
          
          system("tar", "-czf", "sre.tar.gz", "-C", "temp-repo", ".")
          system("rm", "-rf", "temp-repo")
          success = File.exist?("sre.tar.gz") && File.size("sre.tar.gz") > 0
        end
      end
    end
    
    unless File.exist?("sre.tar.gz") && File.size("sre.tar.gz") > 0
      odie <<~EOS
        ❌ Failed to download repository. Please try one of these:
        
        1. Set GitHub token:
           GITHUB_TOKEN=ghp_xxxxxxxxxxxx brew install kdiff
        
        2. Login with GitHub CLI:
           gh auth login
           brew install kdiff
        
        3. Configure SSH key for GitHub and try again
        
        Get token from: https://github.com/settings/tokens (with 'repo' scope)
      EOS
    end
    
    puts "✅ Download successful"
    
    system "tar", "-xzf", "sre.tar.gz", "--strip-components=1"
    
    puts "🔨 Building kdiff..."
    
    cd "utils/kdiff" do
      File.write("kdiff_standalone", "#!/bin/bash\n")
      
      Dir["lib/*.sh"].sort.each do |lib_file|
        File.open("kdiff_standalone", "a") do |f|
          f.puts "\n# === #{File.basename(lib_file)} ==="
          f.write(File.read(lib_file))
          f.puts ""
        end
      end
      
      if File.exist?("kdiff.sh")
        kdiff_content = File.readlines("kdiff.sh")[1..-1].reject { |line| 
          line.strip.start_with?("source") && line.include?("lib/")
        }.join
        
        File.open("kdiff_standalone", "a") do |f|
          f.puts "\n# === Main Script ==="
          f.write(kdiff_content)
        end
      end
      
      system "chmod", "+x", "kdiff_standalone"
      bin.install "kdiff_standalone" => "kdiff"
    end
    
    puts "🎉 kdiff installed successfully!"
  end
  
  test do
    system "#{bin}/kdiff", "--help"
  end
end