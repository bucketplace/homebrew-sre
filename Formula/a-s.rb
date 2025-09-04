class As < Formula
    desc "Akamai Staging IP Management"
    homepage "https://github.com/bucketplace/homebrew-sre"
    url "https://github.com/bucketplace/homebrew-sre/archive/refs/tags/v0.0.7.tar.gz"
    
    def install
      cd "utils/a-s" do
        system "chmod", "+x", "a-s.sh"
        bin.install "a-s.sh" => "a-s"
      end
    end
  end