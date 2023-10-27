/* PostgreSQL */
#include "postgres.h"
#if PG_VERSION_NUM >= 120000
#include "funcapi.h"
#include "access/htup_details.h"
#include "access/stratnum.h"
#include "catalog/namespace.h"
#include "catalog/pg_opfamily.h"
#include "catalog/pg_type_d.h"
#include "catalog/pg_am_d.h"
#include "nodes/supportnodes.h"
#include "nodes/nodeFuncs.h"
#include "nodes/makefuncs.h"
#include "optimizer/optimizer.h"
#include "parser/parse_func.h"
#include "parser/parse_oper.h"
#include "parser/parse_type.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "utils/numeric.h"
#include "utils/selfuncs.h"
#include "utils/syscache.h"

#include "point.h"
#include "pgs_healpix.h"
#include "pgs_moc.h"

PG_FUNCTION_INFO_V1(healpix_dwithin_supportfn);
Datum healpix_dwithin_supportfn(PG_FUNCTION_ARGS)
{
	Node *rawreq = (Node *) PG_GETARG_POINTER(0);
	Node *ret = NULL;

	if (IsA(rawreq, SupportRequestSelectivity))
	{
		SupportRequestSelectivity *req = (SupportRequestSelectivity *) rawreq;
		Node *radiusarg = (Node *) list_nth(req->args, 3);
		ereport(DEBUG1, (errmsg("healpix_dwithin_supportfn sel called on %d", req->funcid)));

		/*
		 * If the radius is a constant, compute the circle constant.
		 */
		if (IsA(radiusarg, Const))
		{
			Const	*constarg = (Const *) radiusarg;
			float8	 radius = DatumGetFloat8(constarg->constvalue);
			req->selectivity = spherecircle_area_float(radius) / SPHERE_SURFACE;
			ereport(DEBUG1, (errmsg("healpix_dwithin_supportfn const radius %g", radius)));
		}
		else
		{
			req->selectivity = DEFAULT_SCIRCLE_SEL;
			ereport(DEBUG1, (errmsg("healpix_dwithin_supportfn non-const radius")));
		}

		CLAMP_PROBABILITY(req->selectivity);
		ereport(DEBUG1, (errmsg("healpix_dwithin_supportfn selectivity %g is_join %d", req->selectivity, req->is_join)));
		ret = rawreq;
	}

	else if (IsA(rawreq, SupportRequestIndexCondition))
	{
		SupportRequestIndexCondition *req = (SupportRequestIndexCondition *) rawreq;

		FuncExpr *clause = (FuncExpr *) req->node;

		Const *orderarg = (Const *) linitial(clause->args);
		Node *leftarg, *rightarg;
		/* TODO: this works on pixel centers, add some slack? */
		Const *radiusarg = (Const *) lfourth(clause->args);

		Expr *pixel_expr;
		ScalarArrayOpExpr *expr;

		Assert(req->opfamily == INTEGER_BTREE_FAM_OID);

		if (! IsA(orderarg, Const))
		{
			ereport(DEBUG1, (errmsg("healpix_dwithin_supportfn called with non-const order argument")));
			PG_RETURN_POINTER(NULL);
		}

		/*
		 * Extract "leftarg" as the arg matching the index and "rightarg" as
		 * the other, even if they were in the opposite order in the call.
		 */
		if (req->indexarg == 1)
		{
			leftarg = lsecond(clause->args);
			rightarg = lthird(clause->args);
		}
		else if (req->indexarg == 2)
		{
			leftarg = lthird(clause->args);
			rightarg = lsecond(clause->args);
		}
		else
		{
			ereport(DEBUG1, (errmsg("healpix_dwithin_supportfn called without indexable healpix arguments")));
			PG_RETURN_POINTER(NULL);
		}

		Assert(exprType(leftarg) == INT8OID);
		Assert(exprType(rightarg) == INT8OID);

		/*
		 * If the order, the right argument and the radius are a constant,
		 * compute the healpixels in the disc. (makeFuncExpr won't constify by
		 * itself unfortunately.)
		 */
		if (IsA(orderarg, Const) && IsA(rightarg, Const) && IsA(radiusarg, Const))
		{
			Datum	 order = ((Const *) orderarg)->constvalue;
			Datum	 center = ((Const *) rightarg)->constvalue;
			Datum	 radius = ((Const *) radiusarg)->constvalue;
			Datum	 pixels = DirectFunctionCall3(healpix_disc, order, center, radius);

			pixel_expr = (Expr *) makeConst(INT8ARRAYOID, -1, InvalidOid,
					-1, pixels, false, false);
			ereport(DEBUG1, (errmsg("healpix_dwithin_supportfn index condition const")));
		}
		else
		{
			List   *func_name = list_make1(makeString("healpix_disc"));
			Oid		args[] = { INT4OID, INT8OID, FLOAT8OID };
			Oid		healpix_disc_oid = LookupFuncName(func_name, 3, args, false);

			pixel_expr = (Expr *) makeFuncExpr(healpix_disc_oid, INT8ARRAYOID,
				list_make3(orderarg, rightarg, radiusarg),
				InvalidOid, InvalidOid, COERCE_EXPLICIT_CALL);
			ereport(DEBUG1, (errmsg("healpix_dwithin_supportfn index condition not const")));
		}

		if (!is_pseudo_constant_for_index(
#if PG_VERSION_NUM >= 140000
					req->root,
#endif
					rightarg, req->index))
			PG_RETURN_POINTER((Node*)NULL);

		{
			List   *oper_name = list_make1(makeString("="));
			Oid		eq_opr_oid = LookupOperName(NULL, oper_name, INT8OID, INT8OID, false, -1);

			expr = makeNode(ScalarArrayOpExpr);
			expr->opno = eq_opr_oid;
			expr->useOr = true;
			expr->args = list_make2(leftarg, pixel_expr);
		}

		ret = (Node *)(list_make1(expr));

		/* This is an exact index lookup */
		req->lossy = false;
	}

	PG_RETURN_POINTER(ret);
}

#endif /* PG_VERSION_NUM */
