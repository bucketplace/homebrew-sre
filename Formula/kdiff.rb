class Kdiff < Formula
  desc "Kubernetes diff tool for comparing deployments and configurations"
  homepage "https://github.com/bucketplace/sre"
  url "file:///dev/null"
  version "0.0.1"
  
  def install
    github_token = ENV["GITHUB_TOKEN"] || ENV["HOMEBREW_GITHUB_API_TOKEN"]
    
    if github_token.nil? || github_token.empty?
      puts <<~EOS
        
        ⚠️  GitHub token required for private repository access.
        
        Run this command with your token:
        
        GITHUB_TOKEN=ghp_xxxxxxxxxxxx brew install kdiff
        
        Get your token from: https://github.com/settings/tokens
        (Make sure to select 'repo' scope for private repository access)
        
      EOS
      exit 1
    end
    
    puts "🔍 Downloading private repository..."
    
    success = system("curl", "-L", 
                     "-H", "Authorization: token #{github_token}",
                     "-H", "Accept: application/vnd.github.v3+json",
                     "https://api.github.com/repos/bucketplace/sre/tarball/v#{version}",
                     "-o", "sre.tar.gz",
                     "--fail", "--silent", "--show-error")
    
    unless success
      puts "❌ Download failed. Please check:"
      puts "  • Token has 'repo' scope"  
      puts "  • You have access to bucketplace/sre"
      puts "  • Token is valid: #{github_token[0..7]}..."
      exit 1
    end
    
    unless File.exist?("sre.tar.gz") && File.size("sre.tar.gz") > 0
      puts "❌ Download file is empty or missing"
      exit 1
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
      
      kdiff_content = File.readlines("kdiff.sh")[1..-1].reject { |line| 
        line.strip.start_with?("source") && line.include?("lib/")
      }.join
      
      File.open("kdiff_standalone", "a") do |f|
        f.puts "\n# === Main Script ==="
        f.write(kdiff_content)
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