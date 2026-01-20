(ns build-injector.core
  "Core logic for injecting build configuration into deps.edn files.

  Clojure's tools.build requires a :build alias in deps.edn that specifies:
  1. The build namespace containing build functions (jar, uberjar, etc.)
  2. Dependencies needed for the build (typically tools.build itself)

  This tool adds or updates the :build alias to ensure projects can be
  built with a standard `clojure -T:build` invocation.

  Example transformation - given an empty deps.edn:
    {}

  After injection with namespace 'build' and tools.build 0.10.6:
    {:aliases {:build {:ns-default build
                       :deps {io.github.clojure/tools.build {:mvn/version \"0.10.6\"}}}}}"
  (:require [clojure.edn :as edn]))

(defn inject-build-namespace
  "Set the default namespace for the :build alias.

  The :ns-default tells `clojure -T:build` which namespace contains the
  build functions (like jar, uberjar, install). This is typically 'build'
  corresponding to a build.clj file at the project root.

  Creates the nested :aliases :build structure if it doesn't exist.

  Parameters:
    m  - The deps.edn map
    ns - The build namespace (typically 'build' or a symbol)"
  [m ns]
  (assoc-in m [:aliases :build :ns-default] ns))

(defn inject-build-dependencies
  "Add dependencies required for the build process.

  This adds dependencies to :aliases :build :deps, which are only available
  when running with the -T:build alias. Typically this includes tools.build
  and any other build-time dependencies.

  Parameters:
    deps     - The deps.edn map
    inj-deps - Map of {\"group/artifact\" \"version\"} to inject

  The function converts string coordinates to symbols and wraps versions
  in :mvn/version maps as required by tools.deps.

  Example:
    (inject-build-dependencies {} {\"io.github.clojure/tools.build\" \"0.10.6\"})
    ;; => {:aliases {:build {:deps {io.github.clojure/tools.build
    ;;                               {:mvn/version \"0.10.6\"}}}}}"
  [deps inj-deps]
  (update-in deps [:aliases :build :deps]
             (fn [existing-deps]
               ;; Merge new deps with any existing build dependencies
               (merge existing-deps
                      (into {}
                            (map (fn [[dep ver]]
                                   ;; Convert string coord to symbol and wrap version
                                   {(symbol dep) {:mvn/version ver}}))
                            inj-deps)))))
