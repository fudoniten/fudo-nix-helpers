(ns build-injector.cli
  "Command-line interface for the build configuration injector.

  This tool reads a deps.edn file, adds or updates the :build alias with
  the specified namespace and dependencies, and prints the result to stdout.

  Usage:
    build-injector --deps-file deps.edn --build-namespace build \\
                   io.github.clojure/tools.build 0.10.6

  The output can be redirected to create a new deps.edn file:
    build-injector --deps-file deps.edn --build-namespace build \\
                   io.github.clojure/tools.build 0.10.6 > new-deps.edn

  This is typically chained after the dependency injector:
    injector --deps-file deps.edn my.lib /path/to/lib.jar | \\
    build-injector --deps-file /dev/stdin --build-namespace build ..."
  (:require [clojure.edn :as edn]
            [clojure.pprint :refer [pprint]]
            [clojure.string :as str]
            [clojure.tools.cli :refer [parse-opts]]
            [build-injector.core :refer [inject-build-dependencies
                                         inject-build-namespace]])
  (:gen-class))

;; Command-line option definitions for tools.cli
(def cli-opts
  [[nil "--deps-file DEPS_FILE" "Source deps.edn file."]
   [nil "--build-namespace NAMESPACE" "Namespace in which to find build functions."]])

(defn- usage
  "Generate a usage message combining any errors with the options summary."
  [summary errors]
  (->> (concat errors ["usage: build-injector [opts] [[<library> <version>] ...]"
                       ""
                       "Options:"
                       summary])
       (str/join \newline)))

(defn -main
  "Entry point for the build-injector CLI.

  Parses command-line arguments, reads the deps.edn file, injects the
  build configuration, and prints the result to stdout."
  [& args]
  (let [{:keys [options arguments errors summary]} (parse-opts args cli-opts)
        ;; Parse positional arguments as pairs: [lib-coord version lib-coord version ...]
        ;; These become build-time dependencies in the :build alias
        inj-deps (into {} (for [[k v] (partition 2 arguments)] [(symbol k) v]))]

    ;; Handle parsing errors
    (when (seq errors)
      (.println *err* (usage summary errors))
      (System/exit 1))

    ;; Validate required --deps-file option
    (when (not (contains? options :deps-file))
      (.println *err* (usage summary ["missing required argument: deps-file"]))
      (System/exit 1))

    ;; Validate required --build-namespace option
    (when (not (contains? options :build-namespace))
      (.println *err* (usage summary ["missing required argument: build-namespace"]))
      (System/exit 1))

    ;; Read deps.edn, inject build config, and print result
    ;; Order matters: inject dependencies first, then set namespace
    (let [deps (-> options :deps-file (slurp) (edn/read-string))]
      (pprint (-> deps
                  (inject-build-dependencies inj-deps)
                  (inject-build-namespace (:build-namespace options)))))

    (System/exit 0)))
