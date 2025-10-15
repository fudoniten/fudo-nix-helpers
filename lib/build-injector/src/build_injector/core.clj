(ns build-injector.core
  (:require [clojure.edn :as edn]))

(defn inject-build-namespace
  "Set the :ns-default for the build alias, creating the nested structure if needed."
  [m ns]
  (assoc-in m [:aliases :build :ns-default] ns))

(defn inject-build-dependencies
  "Add build-specific dependencies declared on the command line.

  inj-deps is a map of dependency coordinates (group/artifact strings) to
  Maven versions.  We normalise the coordinates into symbols and attach the
  appropriate :mvn/version metadata so that tools.deps can resolve them."
  [deps inj-deps]
  (update-in deps [:aliases :build :deps]
             (fn [existing-deps]
               (merge existing-deps
                      (into {}
                            (map (fn [[dep ver]]
                                   {(symbol dep) { :mvn/version ver }}))
                            inj-deps)))))
