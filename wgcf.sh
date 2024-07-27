        # 定义要添加的条目
        entries=(
"2a01:4f8:c010:d56::2 github.com"
"2a01:4f8:c010:d56::3 api.github.com"
"2a01:4f8:c010:d56::4 codeload.github.com"
"2a01:4f8:c010:d56::5 objects.githubusercontent.com"
"2a01:4f8:c010:d56::6 ghcr.io"
"2a01:4f8:c010:d56::7 pkg.github.com npm.pkg.github.com maven.pkg.github.com nuget.pkg.github.com rubygems.pkg.github.com"
)

		# 检查并添加缺失的条目
		for entry in "${entries[@]}"; do
		  if ! grep -qF "$entry" /etc/hosts; then
			echo "$entry" >> /etc/hosts
			echo "Added: $entry"
		  else
			echo "Already exists: $entry"
		  fi
		done
