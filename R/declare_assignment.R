#' Declare assignment procedure
#'
#' @inheritParams declare_internal_inherit_params
#'
#' @return An assignment declaration, which is a function that takes a data.frame as an argument and returns a data.frame with additional columns appended including an assignment variable and (optionally) probabilities of assignment.
#' @export
#'
#' @details
#'
#' \code{declare_assignment} can work with any assignment_function that takes data and returns data. The default handler is \code{conduct_ra} from the \code{randomizr} package. This allows quick declaration of many assignment schemes that involve simple or complete random assignment with blocks and clusters.
#' The arguments to \code{\link{conduct_ra}} can include \code{N}, \code{block_var}, \code{clust_var}, \code{m}, \code{m_each}, \code{prob}, \code{prob_each}, \code{block_m}, \code{block_m_each}, \code{block_prob}, \code{block_prob_each}, \code{num_arms}, and \code{conditions}.
#' The arguments you need to specify are different for different designs. For details see the help files for \code{\link{complete_ra}}, \code{\link{block_ra}}, \code{\link{cluster_ra}}, or \code{\link{block_and_cluster_ra}}.
#'
#' By default, \code{declare_assignment} declares a simple random assignment with probability 0.5.
#' 
#' Custom assignment handlers should augment the data frame with an appropriate column for the assignment(s).
#'
#' @importFrom randomizr declare_ra
#'
#' @examples
#'
#' 
#' # let's work with the beginnings of a design
#' 
#' design <-
#' declare_population(N = 100,
#'                    female = rbinom(N, 1, 0.5),
#'                    U = rnorm(N)) +
#'   # building in treatment effect heterogeneity for fun
#'   declare_potential_outcomes(Y ~ 0.5 * Z + 0.2 * female + 0.1 * Z * female + U)
#'
#'
#' # Declare simple (or "Bernoulli", or "coin flip) random assignment
#' 
#' design_with_assignment <- design + declare_assignment(prob = 0.5, simple = TRUE)
#'
#' head(draw_data(design_with_assignment))
#'
#' # Declare assignment of m units to treatment
#' design + declare_assignment(m = 50)
#' 
#' # Declare assignment of exactly half of the  units to treatment
#' design + declare_assignment(prob = 0.5)
#' 
#' # Declare blocked assignment
#' design + declare_assignment(blocks = female)
#' 
#' # Declare assignment specifying assignment probability for each block
#' design + declare_assignment(block_prob = c(1/3, 2/3), blocks = female)
#' 
#' # Declare factorial assignment (Approach 1): Use complete random assignment 
#' # to assign Z1 and then use Z1 as a block to assign Z2.
#' 
#' design <-
#'   declare_population(N = 100,
#'                    U = rnorm(N)) +
#'   declare_potential_outcomes(Y ~ Z1 + Z2 + Z1*Z2 + U, 
#'                              conditions = list(Z1 = 0:1, Z2 = 0:1)) 
#' 
#' 
#' design +
#'   declare_assignment(assignment_variable = "Z1") +
#'   declare_assignment(blocks = Z1, assignment_variable = "Z2")
#' 
#' 
#' 
#' # Declare factorial assignment (Approach 2): 
#' #   Assign to four conditions and then split into separate factors. 
#' 
#' design +
#'   declare_assignment(conditions = 1:4) + 
#'   declare_step(fabricate, Z1 = as.numeric(Z %in% 2:3), Z2 = as.numeric(Z %in% 3:4))
#' 
#' 
#' 
#' # Declare clustered assignment
#' 
#' clustered_design <-
#'   declare_population(
#'     classrooms = add_level(25, cluster_shock = rnorm(N, sd = 0.5)),
#'     students = add_level(5, individual_shock = rnorm(N, sd = 1.0))
#'   ) +
#'   declare_potential_outcomes(Y ~ 0.5* Z + cluster_shock + individual_shock)
#' 
#' clustered_design + declare_assignment(clusters = classrooms)
#' 
#'    
#' # Declare assignment using custom handler
#'
#' custom_assignment <- function(data, assignment_variable = "X") {
#'  data[, assignment_variable] <- rbinom(n = nrow(data),
#'                                        size = 1,
#'                                        prob = 0.5)
#'  data
#'  }
#'  
#'  declare_population(N = 6) + 
#'    declare_assignment(handler = custom_assignment, assignment_variable = "X")
#'    
declare_assignment <- make_declarations(assignment_handler, "assignment")


#' @importFrom rlang quos !!! call_modify eval_tidy quo f_rhs
#' @importFrom randomizr conduct_ra obtain_condition_probabilities
#' @param assignment_variable Name for assignment variable (quoted). Defaults to "Z". Argument to be used with default handler. 
#' @param append_probabilities_matrix Should the condition probabilities matrix be appended to the data? Defaults to FALSE.  Argument to be used with default handler.
#' @param data A data.frame.
#' @rdname declare_assignment
assignment_handler <-
  function(data, ..., assignment_variable = "Z", append_probabilities_matrix = FALSE) {
    options <- quos(...)

    decl <- eval_tidy(quo(declare_ra(N = !!nrow(data), !!!options)), data)    
    
    for (assn in assignment_variable) {
      cond_prob <- as.symbol(paste0(assn, "_cond_prob"))
      assn <- as.symbol(assn)
      if(append_probabilities_matrix) {
        # Creates Z.prob_1 cols
        data <- fabricate(data, !!assn := !!decl$probabilities_matrix, ID_label = NA)
        # change to underscore
        names(data) <- sub(paste0("(?<=",assn,")[.]"), "_", names(data), perl = TRUE)
      }
        
      data <- fabricate(data,
        !!assn := conduct_ra(!!decl),
        !!cond_prob := obtain_condition_probabilities(!!decl, assignment = !!assn),
        ID_label = NA
      )
    }

    data
  }

validation_fn(assignment_handler) <- function(ret, dots, label) {
  declare_time_error_if_data(ret)

  dirty <- FALSE

  if (!"declaration" %in% names(dots)) {
    if ("blocks" %in% names(dots)) {
      if (class(f_rhs(dots[["blocks"]])) == "character") {
        declare_time_error("Must provide the bare (unquoted) block variable name to blocks.", ret)
      }
    }

    if ("clusters" %in% names(dots)) {
      if (class(f_rhs(dots[["clusters"]])) == "character") {
        declare_time_error("Must provide the bare (unquoted) cluster variable name to clusters.", ret)
      }
    }

    ra_args <- setdiff(names(dots), names(formals(assignment_handler))) # removes data and assignment_variable

    ra_dots <- dots[ra_args]

    if (length(ra_dots) > 0) {
      declaration <- tryCatch(eval_tidy(quo(declare_ra(!!!ra_dots))), error = function(e) e)

      if (inherits(declaration, "ra_declaration")) {
        # message("Assignment declaration factored out from execution path.")
        dots[ra_args] <- NULL
        dots$declaration <- declaration
        dirty <- TRUE
      }
    }
  }

  if ("assignment_variable" %in% names(dots)) {
    if (class(f_rhs(dots[["assignment_variable"]])) == "NULL") {
      declare_time_error("Must provide assignment_variable.", ret)
    }
    assn <- reveal_nse_helper(dots$assignment_variable)

    dots$assignment_variable <- assn

    dirty <- TRUE
  } else {
    assn <- formals(assignment_handler)$assignment_variable
  }

  if (dirty) {
    ret <- build_step(currydata(assignment_handler, dots),
      handler = assignment_handler,
      dots = dots,
      label = label,
      step_type = attr(ret, "step_type"),
      causal_type = attr(ret, "causal_type"),
      call = attr(ret, "call")
    )
  }

  structure(ret, step_meta = list(assignment_variables = assn))
}
