# Original source: https://coderwall.com/p/aridag


# clear the previous precompile task
Rake::Task["deploy:assets:precompile"].clear_actions
class PrecompileRequired < StandardError;
end

set :assets_prefix, 'packs'

namespace :deploy do
  namespace :assets do
    desc "Precompile assets"
    task :precompile do
      on roles(fetch(:assets_roles)) do
        within release_path do
          with rails_env: fetch(:rails_env) do
            begin
              # find the most recent release
              latest_release = File.basename(capture(:readlink, current_path))

              # precompile if this is the first deploy
              raise PrecompileRequired unless latest_release

              latest_release_path = releases_path.join(latest_release)

              latest_node_modules_path = latest_release_path.join(fetch(:node_modules_path))

              execute(:test, '-e', latest_node_modules_path.to_s) rescue raise PrecompileRequired

              release_node_modules_path = release_path.join(fetch(:node_modules_path))
              begin
                execute(:test, '-L', release_node_modules_path.to_s)
              rescue
                execute(:cp, '-r', latest_node_modules_path, release_node_modules_path.parent)
              end

              # precompile if the previous deploy failed to finish precompiling
              execute(:ls, latest_release_path.join('assets_manifest_backup')) rescue raise(PrecompileRequired)

              fetch(:assets_dependencies).each do |dep|
                release = release_path.join(dep)
                latest = latest_release_path.join(dep)

                # skip if both directories/files do not exist
                next if [release, latest].map{|d| test "[ -e #{d} ]"}.uniq == [false]

                # execute raises if there is a diff
                execute(:diff, '-Nqr', release, latest) rescue raise(PrecompileRequired)
              end

              fetch(:assets_shared_dependencies).each do |dep|
                shared_file = shared_path.join(dep)
                execute(:test, latest_release_path, '-nt', shared_file) rescue raise(PrecompileRequired)
              end

              info("Skipping asset precompile, no asset diff found")

              # copy over all of the assets from the last release
              release_asset_path = release_path.join('public', fetch(:assets_prefix))
              # skip if assets directory is symlink
              begin
                execute(:test, '-L', release_asset_path.to_s)
              rescue
                execute(:cp, '-r', latest_release_path.join('public', fetch(:assets_prefix)), release_asset_path.parent)
              end

              # copy assets if manifest file is not exist (this is first deploy after using symlink)
              execute(:ls, release_asset_path.join('manifest*')) rescue raise(PrecompileRequired)

            rescue PrecompileRequired
              execute(:rake, "assets:precompile")
            end
          end
        end
      end
    end
  end
end

namespace :load do
  task :defaults do
    set :assets_dependencies, fetch(:assets_dependencies, [
                                      'package.json',
                                      '.babelrc',
                                      '.postcssrc.yml',
                                      'app/javascript',
                                      'config/webpack',
                                      'config/webpacker.yml',
                                      'yarn.lock'
                                    ])
    set :node_modules_path, fetch(:node_modules_path, 'node_modules')
    set :assets_shared_dependencies, fetch(:assets_shared_dependencies, [])
  end
end
