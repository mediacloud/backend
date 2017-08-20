import numpy as np
import logging

from typing import List
from numpy.polynomial import polynomial


class OptimalFinder:
    """Given a list of data points,
    identify the best fit polynomial equation,
    and find the root point(s) which is the max/min value"""

    @staticmethod
    def _identify_equation(x: List[int],
                           y: List[float],
                           degree: int=2,
                           accuracy: int=10) -> List[int]:
        """
        Identify the polynomial equation of x and y
        :param x: a list of x values
        :param y: a list of y values
        :param degree:c
        :param accuracy: the number of decimal places to keep
        :return: coefficient of polynomials, params[i] * x^(degree-i)
        """
        params = [round(number=param, ndigits=accuracy)
                  for param in np.polyfit(x=x, y=y, deg=degree)][::-1]
        logging.warning(msg="Equation params = {}".format(params))
        return params

    @staticmethod
    def _find_roots(params: List[int]=None,
                    accuracy: int=10) -> List[int]:
        """
        Find the root of a polynomial equation
        :param params: parameters of polynomial equation, params[i] * x^(degree-i)
        :param accuracy: the number of decimal places to keep
        :return: the list of roots
        """
        roots = [round(number=root, ndigits=accuracy)
                 for root in np.roots(params)]
        logging.warning(msg="Equation roots = {}".format(roots))
        return roots

    def find_extreme(self,
                     x: List[int],
                     y: List[float],
                     degree: int=2) -> List[int]:
        """
        Find out the extreme value of the polynomial via derivative
        :param x: a list of x values
        :param y: a list of y values
        :param degree: max power of x
        :return: the list of extreme values
        """
        params = self._identify_equation(x=x, y=y, degree=degree)
        first_der_params = [param for param in polynomial.polyder(params)][::-1]
        logging.warning(msg="First Derivative Parameters = {}".format(first_der_params))
        roots = self._find_roots(params=first_der_params)
        return roots
