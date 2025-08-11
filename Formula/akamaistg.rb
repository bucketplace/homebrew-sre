class Akamaistg < Formula
  desc "Akamai staging/prod test utility"
  homepage "https://github.com/bucketplace/homebrew-sre"
  url "https://github.com/bucketplace/homebrew-sre/archive/refs/tags/v0.0.4.tar.gz"

  def install
    cd "utils/akamaistg" do
      # Install into libexec and create a thin wrapper in bin
      libexec.install "akamaistg.sh", Dir["lib/*.sh"], "akamaistg_targets.yaml"

      (bin/"akamaistg").write <<~EOS
        #!/bin/bash
        exec "#{libexec}/akamaistg.sh" "$@"
      EOS
      (bin/"akamaistg").chmod 0755
    end
  end

  test do
    system "#{bin}/akamaistg", "help"
  end
end


