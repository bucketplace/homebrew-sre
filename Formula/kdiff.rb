class Kdiff < Formula
  desc "Kubernetes diff tool for comparing deployments and configurations"
  homepage "https://github.com/bucketplace/sre"
  url "file:///dev/null"
  version "0.0.1"
  
  def install
    unless system("which gh >/dev/null 2>&1")
      odie "GitHub CLI (gh) is required. Install it with: brew install gh"
    end
    
    unless system("gh auth status >/dev/null 2>&1")
      odie "Please login to GitHub CLI first: gh auth login"
    end
    
    puts "🔍 Downloading via GitHub CLI..."
    
    success = system("gh", "api", "/repos/bucketplace/sre/tarball/v#{version}",
                     "-H", "Accept: application/vnd.github+json",
                     "--jq", ".",
                     "-o", "sre.tar.gz")
    
    unless success && File.exist?("sre.tar.gz") && File.size("sre.tar.gz") > 0
      odie "❌ Failed to download. Check access to bucketplace/sre repository"
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
  
  def caveats
    <<~EOS
      This formula requires GitHub CLI (gh) authentication.
      If not already done, please run: gh auth login
    EOS
  end
  
  test do
    system "#{bin}/kdiff", "--help"
  end
end